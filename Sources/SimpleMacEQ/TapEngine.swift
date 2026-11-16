import CoreAudio
import EQCore
import Foundation

struct TapEngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String, status: OSStatus? = nil) {
        if let status {
            self.message = "\(message) (error \(status))"
        } else {
            self.message = message
        }
    }
}

/// Routes all system audio through the equalizer for one output device.
///
/// A global Core Audio process tap captures (and mutes) everything other apps
/// play. A private aggregate device combines that tap with the real output
/// device, and an IO proc copies the tapped audio through the EQ to the device.
/// The system default output stays the real device, so volume keys keep working.
final class TapEngine {
    let processor: EQProcessor

    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProcID: AudioDeviceIOProcID?
    private var renderer: Renderer?

    init(outputDevice: AudioDeviceID, outputUID: String) throws {
        // The aggregate device runs at the rate of its main sub-device, the output device.
        processor = EQProcessor(sampleRate: AudioHAL.nominalSampleRate(outputDevice) ?? 48_000)

        guard let ownProcess = AudioHAL.ownProcessObject() else {
            throw TapEngineError("Could not register with the audio system")
        }

        // 1. Tap everything except our own output (which would feed back).
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        tapDescription.uuid = UUID()
        tapDescription.name = "SimpleMacEQ"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped

        var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr, tapID != 0 else {
            tapID = 0
            throw TapEngineError("Could not create the system audio tap", status: status)
        }

        let tapFormat = AudioHAL.value(
            of: tapID,
            kAudioTapPropertyFormat,
            initial: AudioStreamBasicDescription()
        )
        let tapChannels = Int(tapFormat?.mChannelsPerFrame ?? 2)
        let tapIsPlanar = ((tapFormat?.mFormatFlags ?? 0) & kAudioFormatFlagIsNonInterleaved) != 0

        // 2. Aggregate device: real output device + tap.
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SimpleMacEQ",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                ]
            ],
        ]

        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != 0 else {
            aggregateID = 0
            teardown()
            throw TapEngineError("Could not create the audio routing device", status: status)
        }

        // 3. IO proc, called directly on the realtime IO thread.
        let stereo = AudioHAL.preferredStereoChannels(outputDevice)
        let renderer = Renderer(
            processor: processor,
            tapChannels: tapChannels,
            tapIsPlanar: tapIsPlanar,
            leftChannel: stereo.left,
            rightChannel: stereo.right
        )
        self.renderer = renderer

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) {
            _, inputData, _, outputData, _ in
            renderer.render(input: inputData, output: outputData)
        }
        guard status == noErr, ioProcID != nil else {
            ioProcID = nil
            teardown()
            throw TapEngineError("Could not attach to the audio routing device", status: status)
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            teardown()
            throw TapEngineError("Could not start audio processing", status: status)
        }
    }

    deinit {
        teardown()
    }

    func stop() {
        teardown()
    }

    private func teardown() {
        if aggregateID != 0 {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        ioProcID = nil
        aggregateID = 0

        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        renderer = nil
    }
}

/// The realtime part: copies tapped audio to the output device through the EQ.
private final class Renderer {
    private let processor: EQProcessor
    private let tapChannels: Int
    private let tapIsPlanar: Bool
    private let leftChannel: Int
    private let rightChannel: Int

    init(processor: EQProcessor, tapChannels: Int, tapIsPlanar: Bool, leftChannel: Int, rightChannel: Int) {
        self.processor = processor
        self.tapChannels = tapChannels
        self.tapIsPlanar = tapIsPlanar
        self.leftChannel = leftChannel
        self.rightChannel = rightChannel
    }

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let sampleSize = MemoryLayout<Float>.size

        for buffer in outputs {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        // The tap's stream comes after any input streams of the output device,
        // so it is found at the end of the input buffer list.
        let inputCount = inputs.count
        guard inputCount > 0 else { return }
        let last = inputs[inputCount - 1]
        guard let lastData = last.mData, last.mNumberChannels > 0 else { return }

        var sourceLeft = lastData.assumingMemoryBound(to: Float.self)
        var sourceRight = sourceLeft
        var sourceStride = Int(last.mNumberChannels)
        var sourceFrames = Int(last.mDataByteSize) / (sampleSize * sourceStride)

        if last.mNumberChannels >= 2 {
            sourceRight = sourceLeft + 1
        } else if tapIsPlanar, tapChannels >= 2, inputCount >= 2,
                  let leftData = inputs[inputCount - 2].mData,
                  inputs[inputCount - 2].mNumberChannels == 1 {
            sourceLeft = leftData.assumingMemoryBound(to: Float.self)
            sourceStride = 1
            sourceFrames = min(sourceFrames, Int(inputs[inputCount - 2].mDataByteSize) / sampleSize)
        }

        // Locate the device's left/right channels across its output buffers.
        var destLeft: UnsafeMutablePointer<Float>?
        var destRight: UnsafeMutablePointer<Float>?
        var destLeftStride = 1
        var destRightStride = 1
        var destFrames = Int.max
        var firstChannel: UnsafeMutablePointer<Float>?
        var firstStride = 1
        var firstFrames = 0

        var base = 0
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let data = buffer.mData else {
                base += channels
                continue
            }
            let samples = data.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / (sampleSize * channels)
            if firstChannel == nil {
                firstChannel = samples
                firstStride = channels
                firstFrames = frames
            }
            if leftChannel >= base, leftChannel < base + channels {
                destLeft = samples + (leftChannel - base)
                destLeftStride = channels
                destFrames = min(destFrames, frames)
            }
            if rightChannel >= base, rightChannel < base + channels {
                destRight = samples + (rightChannel - base)
                destRightStride = channels
                destFrames = min(destFrames, frames)
            }
            base += channels
        }

        processor.syncParameters()

        if let destLeft, let destRight, destLeft != destRight {
            let frames = min(sourceFrames, destFrames)
            var s = 0, l = 0, r = 0
            for _ in 0..<frames {
                destLeft[l] = sourceLeft[s]
                destRight[r] = sourceRight[s]
                s += sourceStride
                l += destLeftStride
                r += destRightStride
            }
            processor.process(channel: 0, data: destLeft, stride: destLeftStride, frames: frames)
            processor.process(channel: 1, data: destRight, stride: destRightStride, frames: frames)
        } else if let dest = destLeft ?? destRight ?? firstChannel {
            // Mono (or unknown layout): mix down to a single channel.
            let stride = destLeft != nil ? destLeftStride : (destRight != nil ? destRightStride : firstStride)
            let available = (destLeft != nil || destRight != nil) ? destFrames : firstFrames
            let frames = min(sourceFrames, available)
            var s = 0, d = 0
            for _ in 0..<frames {
                dest[d] = 0.5 * (sourceLeft[s] + sourceRight[s])
                s += sourceStride
                d += stride
            }
            processor.process(channel: 0, data: dest, stride: stride, frames: frames)
        }
    }
}

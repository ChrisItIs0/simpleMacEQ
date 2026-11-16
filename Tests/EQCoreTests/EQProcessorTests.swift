import XCTest
@testable import EQCore

final class EQProcessorTests: XCTestCase {
    private let sampleRate = 48_000.0

    /// Runs a sine through the processor and returns output RMS / input RMS,
    /// measured after the filters have settled.
    private func gainRatio(frequency: Double, gains: [Double], preampDB: Double = 0) -> Double {
        let processor = EQProcessor(sampleRate: sampleRate)
        processor.setParameters(gains: gains, preampDB: preampDB)

        let frames = 48_000
        var input = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            input[i] = Float(0.25 * sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
        var output = input

        // Process in blocks, like the audio callback does.
        let block = 512
        var offset = 0
        output.withUnsafeMutableBufferPointer { buffer in
            while offset < frames {
                let count = min(block, frames - offset)
                processor.syncParameters()
                processor.process(channel: 0, data: buffer.baseAddress! + offset, stride: 1, frames: count)
                offset += count
            }
        }

        func rms(_ samples: ArraySlice<Float>) -> Double {
            let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
            return (sum / Double(samples.count)).squareRoot()
        }
        let tail = (frames / 2)..<frames
        return rms(output[tail]) / rms(input[tail])
    }

    private func flatGains() -> [Double] {
        [Double](repeating: 0, count: EQBands.count)
    }

    func testFlatProfileLeavesSignalUntouched() {
        let processor = EQProcessor(sampleRate: sampleRate)
        processor.setParameters(gains: flatGains(), preampDB: 0)
        processor.syncParameters()

        let input: [Float] = (0..<1024).map { Float(sin(Double($0) * 0.1)) }
        var output = input
        output.withUnsafeMutableBufferPointer {
            processor.process(channel: 0, data: $0.baseAddress!, stride: 1, frames: 1024)
        }
        XCTAssertEqual(input, output)
    }

    func testBoostAtBandCenter() {
        var gains = flatGains()
        gains[10] = 6 // 2 kHz
        let ratio = gainRatio(frequency: 2000, gains: gains)
        XCTAssertEqual(20 * log10(ratio), 6, accuracy: 0.1)
    }

    func testCutAtBandCenter() {
        var gains = flatGains()
        gains[7] = -9 // 500 Hz
        let ratio = gainRatio(frequency: 500, gains: gains)
        XCTAssertEqual(20 * log10(ratio), -9, accuracy: 0.1)
    }

    func testBoostBarelyAffectsDistantFrequencies() {
        var gains = flatGains()
        gains[10] = 12 // 2 kHz
        let ratio = gainRatio(frequency: 100, gains: gains)
        XCTAssertEqual(20 * log10(ratio), 0, accuracy: 0.2)
    }

    func testPreamp() {
        let ratio = gainRatio(frequency: 1000, gains: flatGains(), preampDB: -6)
        XCTAssertEqual(20 * log10(ratio), -6, accuracy: 0.01)
    }

    func testInterleavedStrideOnlyTouchesOwnChannel() {
        let processor = EQProcessor(sampleRate: sampleRate)
        var gains = flatGains()
        gains[8] = 12
        processor.setParameters(gains: gains, preampDB: 0)
        processor.syncParameters()

        var interleaved = [Float](repeating: 0.5, count: 512)
        interleaved.withUnsafeMutableBufferPointer {
            processor.process(channel: 0, data: $0.baseAddress!, stride: 2, frames: 256)
        }
        for i in stride(from: 1, to: 512, by: 2) {
            XCTAssertEqual(interleaved[i], 0.5)
        }
    }

    func testProfileNormalization() {
        let profile = DeviceProfile(deviceName: "Test", isEnabled: true, preampDB: 40, gains: [30, -30])
        XCTAssertEqual(profile.gains.count, EQBands.count)
        XCTAssertEqual(profile.gains[0], 12)
        XCTAssertEqual(profile.gains[1], -12)
        XCTAssertEqual(profile.preampDB, 12)
    }

    func testProfileStoreRoundTrip() {
        let suite = "SimpleMacEQTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var profile = DeviceProfile.flat(deviceName: "Desk Speakers")
        profile.isEnabled = true
        profile.gains[3] = 4.5
        ProfileStore(defaults: defaults).save(profile, forDeviceUID: "uid-1")

        let reloaded = ProfileStore(defaults: defaults)
        XCTAssertEqual(reloaded.profile(forDeviceUID: "uid-1"), profile)
        XCTAssertNil(reloaded.profile(forDeviceUID: "uid-2"))
    }
}

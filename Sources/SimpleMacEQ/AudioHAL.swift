import CoreAudio
import Foundation

/// Small helpers around the Core Audio HAL property API.
enum AudioHAL {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Reads a fixed-size property value. `initial` only provides the type and storage.
    static func value<T>(
        of object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        initial: T
    ) -> T? {
        var addr = address(selector, scope: scope)
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? result : nil
    }

    static func string(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    static func defaultOutputDevice() -> AudioDeviceID? {
        guard let id = value(
            of: systemObject,
            kAudioHardwarePropertyDefaultOutputDevice,
            initial: AudioDeviceID(0)
        ), id != 0 else { return nil }
        return id
    }

    static func deviceUID(_ device: AudioDeviceID) -> String? {
        string(of: device, kAudioDevicePropertyDeviceUID)
    }

    static func deviceName(_ device: AudioDeviceID) -> String? {
        string(of: device, kAudioObjectPropertyName)
    }

    static func nominalSampleRate(_ device: AudioDeviceID) -> Double? {
        guard let rate = value(of: device, kAudioDevicePropertyNominalSampleRate, initial: Float64(0)),
              rate > 0 else { return nil }
        return rate
    }

    /// The zero-based output channels the device uses for stereo left/right.
    static func preferredStereoChannels(_ device: AudioDeviceID) -> (left: Int, right: Int) {
        var addr = address(
            kAudioDevicePropertyPreferredChannelsForStereo,
            scope: kAudioObjectPropertyScopeOutput
        )
        var channels: [UInt32] = [1, 2]
        var size = UInt32(MemoryLayout<UInt32>.size * 2)
        let status = channels.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr, channels[0] >= 1, channels[1] >= 1 else { return (0, 1) }
        return (Int(channels[0]) - 1, Int(channels[1]) - 1)
    }

    /// The HAL process object that represents this app.
    static func ownProcessObject() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject,
            &addr,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &object
        )
        guard status == noErr, object != 0 else { return nil }
        return object
    }
}

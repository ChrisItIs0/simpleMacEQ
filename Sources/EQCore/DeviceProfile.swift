import Foundation

/// The EQ settings remembered for one audio output device.
public struct DeviceProfile: Codable, Equatable {
    public var deviceName: String
    public var isEnabled: Bool
    public var preampDB: Double
    public var gains: [Double]

    public init(deviceName: String, isEnabled: Bool, preampDB: Double, gains: [Double]) {
        self.deviceName = deviceName
        self.isEnabled = isEnabled
        self.preampDB = preampDB
        self.gains = gains
        normalize()
    }

    /// A disabled profile with all bands at 0 dB.
    public static func flat(deviceName: String) -> DeviceProfile {
        DeviceProfile(
            deviceName: deviceName,
            isEnabled: false,
            preampDB: 0,
            gains: [Double](repeating: 0, count: EQBands.count)
        )
    }

    /// Forces the profile into the current band layout and value ranges.
    public mutating func normalize() {
        if gains.count > EQBands.count {
            gains = Array(gains.prefix(EQBands.count))
        } else if gains.count < EQBands.count {
            gains += [Double](repeating: 0, count: EQBands.count - gains.count)
        }
        gains = gains.map { min(max($0, EQBands.gainRange.lowerBound), EQBands.gainRange.upperBound) }
        preampDB = min(max(preampDB, EQBands.preampRange.lowerBound), EQBands.preampRange.upperBound)
    }
}

/// Persists device profiles, keyed by the Core Audio device UID.
public final class ProfileStore {
    private let defaults: UserDefaults
    private let key = "deviceProfiles"
    private var profiles: [String: DeviceProfile]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: DeviceProfile].self, from: data) {
            profiles = decoded.mapValues { profile in
                var profile = profile
                profile.normalize()
                return profile
            }
        } else {
            profiles = [:]
        }
    }

    public func profile(forDeviceUID uid: String) -> DeviceProfile? {
        profiles[uid]
    }

    public func save(_ profile: DeviceProfile, forDeviceUID uid: String) {
        profiles[uid] = profile
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: key)
        }
    }
}

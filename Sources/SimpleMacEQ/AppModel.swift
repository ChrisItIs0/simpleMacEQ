import AppKit
import CoreAudio
import EQCore
import Foundation
import ServiceManagement

/// Tracks the current output device, its profile, and the running EQ engine.
/// All methods are expected to be called on the main thread.
final class AppModel: ObservableObject {
    @Published private(set) var deviceName = "No output device"
    @Published private(set) var deviceUID: String?
    @Published private(set) var profile = DeviceProfile.flat(deviceName: "")
    @Published private(set) var isProcessing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchAtLogin = false

    private let store = ProfileStore()
    private var engine: TapEngine?
    private var deviceID: AudioDeviceID?

    private var sampleRateListener: AudioObjectPropertyListenerBlock?
    private var sampleRateListenerDevice: AudioDeviceID?

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled

        var address = AudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioHAL.systemObject, &address, DispatchQueue.main) {
            [weak self] _, _ in
            self?.refreshDevice()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartEngineSoon()
        }

        refreshDevice()
    }

    // MARK: - User actions

    func setEnabled(_ enabled: Bool) {
        guard deviceUID != nil else { return }
        profile.isEnabled = enabled
        saveProfile()
        applyEngineState()
    }

    func setGain(band: Int, to gain: Double) {
        guard deviceUID != nil, profile.gains.indices.contains(band) else { return }
        profile.gains[band] = gain
        saveProfile()
        pushParameters()
    }

    func setPreamp(_ preampDB: Double) {
        guard deviceUID != nil else { return }
        profile.preampDB = preampDB
        saveProfile()
        pushParameters()
    }

    func resetBands() {
        guard deviceUID != nil else { return }
        profile.gains = [Double](repeating: 0, count: EQBands.count)
        profile.preampDB = 0
        saveProfile()
        pushParameters()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Could not change launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Device tracking

    private func refreshDevice() {
        guard let id = AudioHAL.defaultOutputDevice(), let uid = AudioHAL.deviceUID(id) else {
            stopEngine()
            deviceID = nil
            deviceUID = nil
            deviceName = "No output device"
            profile = .flat(deviceName: "")
            return
        }
        // The notification can fire more than once for the same switch.
        if id == deviceID, uid == deviceUID { return }

        stopEngine()
        errorMessage = nil
        deviceID = id
        deviceUID = uid
        deviceName = AudioHAL.deviceName(id) ?? "Unknown device"
        profile = store.profile(forDeviceUID: uid) ?? .flat(deviceName: deviceName)
        applyEngineState()
    }

    private func saveProfile() {
        guard let deviceUID else { return }
        profile.deviceName = deviceName
        store.save(profile, forDeviceUID: deviceUID)
    }

    // MARK: - Engine

    private func applyEngineState() {
        if profile.isEnabled {
            if engine == nil {
                startEngine()
            } else {
                pushParameters()
            }
        } else {
            stopEngine()
        }
    }

    private func pushParameters() {
        engine?.processor.setParameters(gains: profile.gains, preampDB: profile.preampDB)
    }

    private func startEngine() {
        guard let deviceID, let deviceUID else { return }
        do {
            let engine = try TapEngine(outputDevice: deviceID, outputUID: deviceUID)
            self.engine = engine
            pushParameters()
            isProcessing = true
            errorMessage = nil
            watchSampleRate(of: deviceID)
        } catch {
            engine = nil
            isProcessing = false
            errorMessage = error.localizedDescription
        }
    }

    private func stopEngine() {
        unwatchSampleRate()
        engine?.stop()
        engine = nil
        isProcessing = false
    }

    /// Rebuilds the engine after the device changed underneath it (sample rate, wake).
    private func restartEngineSoon() {
        guard engine != nil else { return }
        stopEngine()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.engine == nil else { return }
            self.applyEngineState()
        }
    }

    private func watchSampleRate(of device: AudioDeviceID) {
        unwatchSampleRate()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.restartEngineSoon()
        }
        var address = AudioHAL.address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, listener) == noErr {
            sampleRateListener = listener
            sampleRateListenerDevice = device
        }
    }

    private func unwatchSampleRate() {
        if let listener = sampleRateListener, let device = sampleRateListenerDevice {
            var address = AudioHAL.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listener)
        }
        sampleRateListener = nil
        sampleRateListenerDevice = nil
    }
}

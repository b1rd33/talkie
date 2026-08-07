import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

private func audioDevicesPropertyAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioDeviceResolution: Equatable, Sendable {
    case preferred(AudioInputDevice)
    case systemDefault(AudioInputDevice?)
    case preferredMissing(requestedUID: String, fallback: AudioInputDevice?)
    case configurationFailed(requestedUID: String?, status: OSStatus)

    var actualDevice: AudioInputDevice? {
        switch self {
        case .preferred(let device): device
        case .systemDefault(let device): device
        case .preferredMissing(_, let fallback): fallback
        case .configurationFailed: nil
        }
    }
}

@MainActor
protocol AudioDeviceCataloging {
    func inputDevices() -> [AudioInputDevice]
    func configure(_ engine: AVAudioEngine, preferredUID: String?) -> AudioDeviceResolution
}

@MainActor
protocol AudioDeviceMonitoring: AnyObject {
    func start(_ onDevicesChanged: @escaping @MainActor ([AudioInputDevice]) -> Void)
    func stop()
}

enum AudioDeviceSelection {
    static func deviceID(preferredUID: String?, devices: [AudioInputDevice]) -> AudioDeviceID? {
        guard let preferredUID else { return nil } // nil means follow the system default
        return devices.first(where: { $0.uid == preferredUID })?.id
    }

    static func resolution(preferredUID: String?, devices: [AudioInputDevice],
                           defaultDeviceID: AudioDeviceID?) -> AudioDeviceResolution {
        let fallback = defaultDeviceID.flatMap { id in devices.first(where: { $0.id == id }) }
        guard let preferredUID else { return .systemDefault(fallback) }
        guard let preferred = devices.first(where: { $0.uid == preferredUID }) else {
            return .preferredMissing(requestedUID: preferredUID, fallback: fallback)
        }
        return .preferred(preferred)
    }

    static func activeDeviceWasRemoved(uid: String?, devices: [AudioInputDevice]) -> Bool {
        guard let uid else { return false }
        return !devices.contains(where: { $0.uid == uid })
    }
}

struct SystemAudioDeviceCatalog: AudioDeviceCataloging {
    func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannelCount(id) > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, device: id),
                  let name = stringProperty(kAudioObjectPropertyName, device: id) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func configure(_ engine: AVAudioEngine, preferredUID: String?) -> AudioDeviceResolution {
        let devices = inputDevices()
        let resolution = AudioDeviceSelection.resolution(
            preferredUID: preferredUID, devices: devices, defaultDeviceID: defaultInputDeviceID())
        guard case .preferred(let device) = resolution else { return resolution }
        guard let unit = engine.inputNode.audioUnit else {
            return .configurationFailed(requestedUID: preferredUID, status: kAudio_ParamError)
        }
        var mutableID = device.id
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
            0, &mutableID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            return .configurationFailed(requestedUID: preferredUID, status: status)
        }
        return .preferred(device)
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector,
                                device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        // CoreAudio writes a CFStringRef into the supplied pointer. Model the
        // reference as Unmanaged so Swift does not expose an object-containing
        // variable as an arbitrary mutable raw buffer.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }

    private func inputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

/// Production CoreAudio listener. It reports the current device snapshot and leaves
/// policy (fallback vs. fail the active capture) to `AudioRecorder`. Default-input
/// changes intentionally take effect on the next recording; removing the device that
/// owns the active capture is detected immediately.
@MainActor
final class SystemAudioDeviceMonitor: AudioDeviceMonitoring {
    private let catalog: SystemAudioDeviceCatalog
    private var listener: AudioObjectPropertyListenerBlock?

    init(catalog: SystemAudioDeviceCatalog? = nil) {
        self.catalog = catalog ?? SystemAudioDeviceCatalog()
    }

    func start(_ onDevicesChanged: @escaping @MainActor ([AudioInputDevice]) -> Void) {
        stop()
        var address = audioDevicesPropertyAddress()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                onDevicesChanged(self.catalog.inputDevices())
            }
        }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr else { return }
        listener = block
    }

    func stop() {
        guard let listener else { return }
        var address = audioDevicesPropertyAddress()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }

    deinit {
        // `stop` is main-actor isolated; normal recording teardown owns deterministic
        // removal. This is only a defensive cleanup for an unexpectedly abandoned monitor.
        guard let listener else { return }
        var address = audioDevicesPropertyAddress()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

}

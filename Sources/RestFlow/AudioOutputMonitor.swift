import CoreAudio
import Foundation

@MainActor
protocol AudioOutputMonitoring: AnyObject {
    func start(onChange: @escaping (_ outputLost: Bool) -> Void)
    func refresh()
    func stop()
}

/// Observe only the current route, without changing the system's selected device or volume.
@MainActor
final class AudioOutputMonitor: AudioOutputMonitoring {
    struct Output: Equatable {
        let id: AudioDeviceID
        let isExternal: Bool
        var jackConnected: Bool? = nil
    }
    struct Snapshot {
        var output: Output?
        var aliveDevices: Set<AudioDeviceID>
    }

    private let readSnapshot: () -> Snapshot?
    private let observesSystem: Bool
    private var previous: Snapshot?
    private var onChange: ((Bool) -> Void)?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var observedDevice: AudioDeviceID?

    init(readSnapshot: (() -> Snapshot?)? = nil) {
        self.readSnapshot = readSnapshot ?? Self.systemSnapshot
        observesSystem = readSnapshot == nil
    }

    func start(onChange: @escaping (Bool) -> Void) {
        stop()
        self.onChange = onChange
        previous = readSnapshot()
        if observesSystem {
            listen(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
            listen(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
            observeDevice(previous?.output?.id)
        }
    }

    func refresh() {
        guard onChange != nil, let current = readSnapshot() else { return }
        let old = previous
        previous = current
        if observesSystem { observeDevice(current.output?.id) }
        guard let old else { return }
        guard let output = old.output else {
            if current.output != nil { onChange?(false) }
            return
        }
        let disappeared = old.aliveDevices.contains(output.id) && !current.aliveDevices.contains(output.id)
        // AirPods can leave the active route while remaining paired/listed by Core Audio.
        // Treat switching away from an external route conservatively, including manual switches.
        let leftExternalRoute = output.isExternal && current.output?.id != output.id
        let unpluggedJack = output.id == current.output?.id && output.jackConnected == true && current.output?.jackConnected == false
        let lost = disappeared || leftExternalRoute || unpluggedJack || current.output == nil
        if lost || current.output != old.output { onChange?(lost) }
    }

    func stop() {
        for (object, var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
        observedDevice = nil
        previous = nil
        onChange = nil
    }

    private func observeDevice(_ id: AudioDeviceID?) {
        guard id != observedDevice else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (object, var address, block) in listeners where object != system {
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll { $0.0 != system }
        observedDevice = id
        if let id {
            listen(object: id, selector: kAudioDevicePropertyDeviceIsAlive)
            listen(object: id, selector: kAudioDevicePropertyJackIsConnected, scope: kAudioDevicePropertyScopeOutput)
        }
    }

    private func listen(object: AudioObjectID, selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    static func systemSnapshot() -> Snapshot? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let selected = uint32(system, kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        if devices.isEmpty { return Snapshot(output: nil, aliveDevices: []) }
        let status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return nil }
        devices = Array(devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
        let alive = Set(devices.filter { uint32($0, kAudioDevicePropertyDeviceIsAlive) != 0 })
        let output: Output?
        if selected == kAudioObjectUnknown { output = nil }
        else {
            output = Output(id: selected, isExternal: uint32(selected, kAudioDevicePropertyTransportType) != kAudioDeviceTransportTypeBuiltIn,
                            jackConnected: uint32(selected, kAudioDevicePropertyJackIsConnected, scope: kAudioDevicePropertyScopeOutput).map { $0 != 0 })
        }
        return Snapshot(output: output, aliveDevices: alive)
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

import AppKit
import Carbon
import RestFlowCore

@MainActor
final class ShortcutController {
    enum Action: UInt32, CaseIterable { case pause = 1, restart, restNow }
    private var registrations: [Action: (KeyboardShortcut, EventHotKeyRef)] = [:]
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    var perform: ((Action) -> Void)?
    var isRecording = false
    var isSuspended = false
    var recordingHandler: ((KeyboardShortcut) -> Void)?
    private let signature: OSType = 0x52464C57 // RFLW

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let controller = Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard id.signature == controller.signature else { return OSStatus(eventNotHandledErr) }
                if !controller.isSuspended,
                   let registration = controller.registrations.first(where: { ShortcutController.hotKeyID($0.value.0) == id.id }) {
                    if CommandLine.arguments.contains("--diagnostics") {
                        print("RestFlow hotkey: Carbon action=\(registration.key)"); fflush(stdout)
                    }
                    if controller.isRecording { controller.recordingHandler?(registration.value.0) }
                    else { controller.perform?(registration.key) }
                }
                return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        // App-directed events (including accessibility automation) can bypass Carbon's global dispatcher.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, !self.isRecording, !self.isSuspended else { return false }
                let chord = KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
                guard let action = self.registrations.first(where: { $0.value.0 == chord })?.key else { return false }
                if !event.isARepeat { self.perform?(action) }
                return true
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        for (_, ref) in registrations.values { UnregisterEventHotKey(ref) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
    }

    /// Keep existing registrations until every replacement has successfully registered.
    func apply(_ settings: AppSettings) throws {
        try settings.validate()
        let desired: [Action: KeyboardShortcut] = [
            .pause: settings.pauseShortcut, .restart: settings.restartShortcut, .restNow: settings.restNowShortcut
        ].compactMapValues { $0 }
        if desired == registrations.mapValues({ $0.0 }) { return }
        guard handler != nil else {
            throw ConfigurationError.invalid(settings.language.text("无法初始化全局快捷键，请重新启动应用。", "Unable to initialize global shortcuts. Restart the app."))
        }
        for shortcut in desired.values {
            if Self.isSystemShortcut(shortcut) {
                throw ConfigurationError.invalid(settings.language.text("快捷键与系统快捷键冲突，请更换。", "This shortcut conflicts with macOS. Choose another."))
            }
        }
        // Reuse matching chords even when two actions exchange shortcuts.
        var pending: [KeyboardShortcut: EventHotKeyRef] = [:]
        do {
            for (_, shortcut) in desired where !registrations.values.contains(where: { $0.0 == shortcut }) {
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                                EventHotKeyID(signature: signature, id: Self.hotKeyID(shortcut)),
                                                GetEventDispatcherTarget(), 0, &ref)
                guard status == noErr, let ref else {
                    throw ConfigurationError.invalid(settings.language.text("快捷键已被系统或其他应用占用，请更换。", "This shortcut is already in use. Choose another."))
                }
                pending[shortcut] = ref
            }
        } catch {
            pending.values.forEach { UnregisterEventHotKey($0) }
            throw error
        }
        for (shortcut, ref) in registrations.values where !desired.values.contains(shortcut) {
            UnregisterEventHotKey(ref)
        }
        var updated: [Action: (KeyboardShortcut, EventHotKeyRef)] = [:]
        for (action, shortcut) in desired {
            let ref = registrations.values.first(where: { $0.0 == shortcut })?.1 ?? pending[shortcut]!
            updated[action] = (shortcut, ref)
        }
        registrations = updated
    }

    private static func hotKeyID(_ shortcut: KeyboardShortcut) -> UInt32 {
        shortcut.keyCode | (shortcut.modifiers << 8)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        (flags.contains(.command) ? UInt32(cmdKey) : 0) |
        (flags.contains(.control) ? UInt32(controlKey) : 0) |
        (flags.contains(.option) ? UInt32(optionKey) : 0) |
        (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }

    static func cocoaModifiers(_ shortcut: KeyboardShortcut) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if shortcut.modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if shortcut.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    static func keyEquivalent(_ shortcut: KeyboardShortcut) -> String {
        let special: [UInt32: UInt16] = [36: 13, 48: 9, 49: 32, 51: 8, 117: 0xF728,
            123: 0xF702, 124: 0xF703, 125: 0xF701, 126: 0xF700,
            122: 0xF704, 120: 0xF705, 99: 0xF706, 118: 0xF707, 96: 0xF708, 97: 0xF709,
            98: 0xF70A, 100: 0xF70B, 101: 0xF70C, 109: 0xF70D, 103: 0xF70E, 111: 0xF70F]
        if let value = special[shortcut.keyCode], let scalar = UnicodeScalar(value) { return String(scalar) }
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let result = UCKeyTranslate(layout, UInt16(shortcut.keyCode), UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKey, characters.count, &length, &characters)
        return result == noErr ? String(utf16CodeUnits: characters, count: length).lowercased() : ""
    }

    static func label(_ shortcut: KeyboardShortcut) -> String {
        let flags = cocoaModifiers(shortcut)
        let symbols = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") +
            (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
        let keys: [UInt32: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦",
                                     123: "←", 124: "→", 125: "↓", 126: "↑"]
        let fKeys: [UInt32] = [122,120,99,118,96,97,98,100,101,109,103,111]
        let key = keys[shortcut.keyCode] ?? fKeys.firstIndex(of: shortcut.keyCode).map { "F\($0 + 1)" } ?? keyEquivalent(shortcut).uppercased()
        return symbols + key
    }

    static func isSystemShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        // Standard application commands and common system reservations do not all appear in the symbolic list.
        let command = UInt32(cmdKey)
        if shortcut.modifiers == command && [0, 6, 7, 8, 9, 12, 13, 35, 48, 49, 50].contains(shortcut.keyCode) { return true }
        if shortcut.modifiers == command | UInt32(shiftKey) && [3, 4, 5].contains(shortcut.keyCode) { return true }
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let list = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        return list.contains { item in
            (item[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
            (item[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode &&
            (item[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == shortcut.modifiers
        }
    }
}

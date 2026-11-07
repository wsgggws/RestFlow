import AppKit
import Carbon
import RestFlowCore

/// Explicit diagnostic entry point: no configuration writes or login-item mutations.
@MainActor
enum SystemIntegrationChecks {
    static func run() -> Int32 {
        let controller = ShortcutController()
        defer { controller.stop() }
        do {
            var settings = AppSettings()
            let chord = KeyboardShortcut(keyCode: 35, modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
            settings.pauseShortcut = chord
            try controller.apply(settings)
            print("PASS native hotkey registration")
            var received: ShortcutController.Action?
            controller.perform = { received = $0 }
            func dispatch(_ shortcut: KeyboardShortcut) throws {
                var event: EventRef?
                guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr, let event else {
                    throw ConfigurationError.invalid("Cannot create diagnostic Carbon event")
                }
                defer { ReleaseEvent(event) }
                var id = EventHotKeyID(signature: 0x52464C57, id: shortcut.keyCode | (shortcut.modifiers << 8))
                guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr,
                      SendEventToEventTarget(event, GetEventDispatcherTarget()) == noErr else {
                    throw ConfigurationError.invalid("Cannot dispatch diagnostic Carbon event")
                }
            }
            try dispatch(chord)
            guard received == .pause else { throw ConfigurationError.invalid("Carbon event did not invoke pause") }
            print("PASS Carbon dispatcher invokes registered action")
            settings.pauseShortcut = nil
            settings.restartShortcut = chord
            try controller.apply(settings)
            try dispatch(chord)
            guard received == .restart else { throw ConfigurationError.invalid("Reassigned Carbon event invoked wrong action") }
            print("PASS shortcut reassignment updates action dispatch")
            settings.restNowShortcut = KeyboardShortcut(keyCode: 49, modifiers: UInt32(cmdKey))
            do {
                try controller.apply(settings)
                print("FAIL system shortcut accepted")
                return 1
            } catch { print("PASS system shortcut conflict rejected") }
            settings.restNowShortcut = nil
            try controller.apply(settings)
            let occupied = KeyboardShortcut(keyCode: 17, modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
            var foreign: EventHotKeyRef?
            let status = RegisterEventHotKey(occupied.keyCode, occupied.modifiers,
                                             EventHotKeyID(signature: 0x54455354, id: 1), GetEventDispatcherTarget(), 0, &foreign)
            guard status == noErr, let foreign else { throw ConfigurationError.invalid("Unable to reserve conflict test key") }
            defer { UnregisterEventHotKey(foreign) }
            settings.restNowShortcut = occupied
            do {
                try controller.apply(settings)
                print("FAIL occupied hotkey accepted")
                return 1
            } catch { print("PASS occupied shortcut rejected without losing existing bindings") }
            received = nil
            try dispatch(chord)
            guard received == .restart else { throw ConfigurationError.invalid("Failed replacement lost original action") }
            print("PASS original bindings survive failed replacement")
            settings.restNowShortcut = nil
            try controller.apply(settings)
            print("PASS macOS modifier display: \(ShortcutController.label(chord))")
            print("PASS login-item status read: \(LoginItemController().status.rawValue)")
            return 0
        } catch { print("FAIL native integration: \(error)"); return 1 }
    }
}

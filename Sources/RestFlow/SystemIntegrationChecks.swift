import AppKit
import SwiftUI
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
        settings.operatingSchedule.enabled = false
            let chord = RestFlowCore.KeyboardShortcut(keyCode: 35, modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
            settings.pauseShortcut = chord
            try controller.apply(settings)
            print("PASS native hotkey registration")
            var received: ShortcutController.Action?
            controller.perform = { received = $0 }
            func dispatch(_ shortcut: RestFlowCore.KeyboardShortcut) throws {
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
            settings.restNowShortcut = RestFlowCore.KeyboardShortcut(keyCode: 49, modifiers: UInt32(cmdKey))
            do {
                try controller.apply(settings)
                print("FAIL system shortcut accepted")
                return 1
            } catch { print("PASS system shortcut conflict rejected") }
            settings.restNowShortcut = nil
            try controller.apply(settings)
            let occupied = RestFlowCore.KeyboardShortcut(keyCode: 17, modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
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
            settings.restartShortcut = nil; settings.focusNoiseShortcut = chord
            try controller.apply(settings); received = nil; try dispatch(chord)
            guard received == .focusNoise else { throw ConfigurationError.invalid("White noise hotkey invoked wrong action") }
            print("PASS white noise Carbon shortcut dispatch")
            controller.isSuspended = true; received = nil; try dispatch(chord)
            guard received == nil else { throw ConfigurationError.invalid("Break did not suspend white noise shortcut") }
            controller.isSuspended = false
            print("PASS break input guard suspends white noise shortcut")
            print("PASS macOS modifier display: \(ShortcutController.label(chord))")
            print("PASS login-item status read: \(LoginItemController().status.rawValue)")
            return 0
        } catch { print("FAIL native integration: \(error)"); return 1 }
    }
}

@MainActor
enum BreakIntegrationChecks {
    static func run() -> Int32 {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-break-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var defaults = AppSettings()
        defaults.operatingSchedule.enabled = false
        defaults.soundEnabled = false
        defaults.checkForUpdatesAutomatically = false
        _ = try? ConfigurationStore(directory: directory).load(orCreate: defaults)
        var current: TimeInterval = 100
        let model = AppModel(directory: directory, clock: { current })
        let controller = BreakWindowController(model: model)
        model.onPhaseChange = { controller.sync() }
        let previousOptions = NSApp.presentationOptions
        defer { controller.close(); model.stop() }
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }
        model.togglePause()
        controller.preview()
        check(model.phase == .shortBreak && !model.isPaused, "preview starts a running short break from paused focus")
        check(NSApp.presentationOptions.contains(.disableProcessSwitching), "Cmd-Tab is disabled while break covers the desktop")
        check(NSApp.windows.filter { $0.isVisible }.allSatisfy { !$0.isOpaque && $0.backgroundColor == .clear }, "break window allows desktop transparency")
        if let host = NSApp.windows.first(where: { $0.isVisible })?.contentView {
            func cornerAlpha() -> CGFloat {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                return bitmap.colorAt(x: 10, y: 10)?.alphaComponent ?? -1
            }
            check(cornerAlpha() > 0.99, "zero transparency paints a fully opaque background")
            model.settings.breakTransparency = 1
            let alpha = cornerAlpha()
            check(alpha >= 0 && alpha < 0.01, "full transparency leaves the window corner clear (alpha=\(alpha))")
            model.settings.breakTransparency = 0.5
            let halfAlpha = cornerAlpha()
            check((0.45...0.55).contains(halfAlpha), "half transparency blends the background with the desktop (alpha=\(halfAlpha))")
            model.settings.breakTransparency = 0
        }
        current += 1
        model.refresh()
        check(model.remaining == defaults.shortBreakSeconds - 1, "short break countdown advances instead of showing a static preview")
        var competingEsc: EventHotKeyRef?
        let occupied = RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x54455354, id: 42),
                                          GetEventDispatcherTarget(), 0, &competingEsc)
        check(occupied != noErr, "global Esc is registered while the break is visible")
        if let competingEsc { UnregisterEventHotKey(competingEsc) }
        NSApp.deactivate()
        NSApp.windows.forEach { $0.resignKey() }
        var event: EventRef?
        if CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr, let event {
            var id = EventHotKeyID(signature: 0x52464252, id: 1) // RFBR, temporary global Esc
            SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id)
            SendEventToEventTarget(event, GetEventDispatcherTarget())
            ReleaseEvent(event)
        }
        check(!NSApp.windows.contains(where: { $0.isVisible }), "Esc closes the break after focus is lost")
        controller.close()
        check(NSApp.presentationOptions == previousOptions, "closing a break restores system presentation options")
        check(model.phase == .work && model.isPaused && !model.shortcuts.isSuspended, "Esc restores the original paused focus and configured shortcuts")
        var releasedEsc: EventHotKeyRef?
        let available = RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x54455354, id: 43),
                                           GetEventDispatcherTarget(), 0, &releasedEsc)
        check(available == noErr, "global Esc is released after leaving the break")
        if let releasedEsc { UnregisterEventHotKey(releasedEsc) }
        controller.preview()
        current += defaults.shortBreakSeconds + 1
        model.refresh()
        check(model.phase == .work && !NSApp.windows.contains(where: { $0.isVisible }) && NSApp.presentationOptions == previousOptions,
              "natural short-break completion closes windows and restores keyboard behavior")
        controller.preview()
        model.restart()
        check(!NSApp.windows.contains(where: { $0.isVisible }) && NSApp.presentationOptions == previousOptions,
              "restart also removes the break input guard")
        model.onSettingsChange = { controller.reconcilePresentation() }
        model.settings.shortMessageID = ReminderMessage.noneID
        model.settings.longMessageID = ReminderMessage.noneID
        model.settings.visualID = BuiltinVisual.noneID
        controller.preview()
        check(model.phase == .shortBreak && !model.isPaused && !NSApp.windows.contains(where: { $0.isVisible }),
              "all-none manual break runs without a full-screen window")
        check(NSApp.presentationOptions == previousOptions && !model.shortcuts.isSuspended,
              "invisible break keeps desktop and configured shortcuts available")
        current += 1
        model.refresh()
        check(model.remaining == defaults.shortBreakSeconds - 1, "invisible short break still counts down")
        model.settings.longMessageID = ReminderMessage.randomID
        check(!NSApp.windows.contains(where: { $0.isVisible }), "random long message does not reveal an all-none short break")
        model.settings.shortMessageID = ReminderMessage.randomID
        check(NSApp.windows.contains(where: { $0.isVisible }) && model.shortcuts.isSuspended,
              "random short message reveals full-screen text even with no animation")
        model.settings.shortMessageID = ReminderMessage.noneID
        check(!NSApp.windows.contains(where: { $0.isVisible }) && NSApp.presentationOptions == previousOptions,
              "switching current content to none closes windows and releases keyboard capture")
        current += defaults.shortBreakSeconds
        model.refresh()
        check(model.phase == .work, "invisible short break naturally returns to focus")
        current += defaults.plan.workDuration
        model.refresh()
        check(model.phase == .shortBreak && !NSApp.windows.contains(where: { $0.isVisible }),
              "natural all-none short break runs without a window")
        current += defaults.shortBreakSeconds
        model.refresh()
        current += defaults.plan.workDuration
        model.refresh()
        check(model.phase == .longBreak && NSApp.windows.contains(where: { $0.isVisible }),
              "natural long break shows its random message independently")
        model.settings.longMessageID = ReminderMessage.noneID
        check(!NSApp.windows.contains(where: { $0.isVisible }) && !model.shortcuts.isSuspended,
              "all-none long break hides windows without interrupting its countdown")
        current += defaults.plan.longBreakDuration
        model.refresh()
        check(model.phase == .work && model.completedWorkSessions == 0 && NSApp.presentationOptions == previousOptions,
              "invisible long break finishes the regular cycle")
        model.settings.shortMessageID = "eyes"
        model.settings.visualID = BuiltinVisual.rings.rawValue
        controller.restNow()
        check(model.phase.isBreak && NSApp.windows.contains(where: { $0.isVisible }), "real rest opens before a simulated screen lock")
        model.setScreenLocked(true)
        check(model.phase == .work && model.isAway && !NSApp.windows.contains(where: { $0.isVisible }) &&
              NSApp.presentationOptions == previousOptions && !model.shortcuts.isSuspended,
              "screen lock closes rest windows and releases input protection immediately")
        model.setScreenLocked(false)
        func scenePixels(_ visual: BuiltinVisual, time: Double, reduced: Bool = false) -> Data? {
            let renderer = ImageRenderer(content: BuiltinVisualView(visual: visual, frameTime: time, reduceMotionOverride: reduced)
                .frame(width: 400, height: 250))
            renderer.scale = 1
            guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return nil }
            return data as Data
        }
        for visual in BuiltinVisual.allCases {
            let first = scenePixels(visual, time: 0), later = scenePixels(visual, time: 1.75)
            check(first != nil && later != nil && first != later, "animated scene changes rendered pixels: \(visual.rawValue)")
        }
        let still = scenePixels(.forest, time: 0, reduced: true)
        check(still != nil && still == scenePixels(.forest, time: 1.75, reduced: true),
              "Reduce Motion freezes animation despite advancing time")
        return failures == 0 ? 0 : 1
    }
}

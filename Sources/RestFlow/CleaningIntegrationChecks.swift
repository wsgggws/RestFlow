import AppKit
import RestFlowCore

@MainActor
enum CleaningIntegrationChecks {
    private final class Output: LoopAudioOutput {
        var volume: Float = 0
        var isPlaying = false
        func play() { isPlaying = true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }

    private final class Input: CleaningInputProtecting {
        var active = false
        var exit: (() -> Void)?
        var failure: ((CleaningProtectionError?) -> Void)?
        func start(progress: @escaping (Double, Bool) -> Void, exit: @escaping () -> Void,
                   failure: @escaping (CleaningProtectionError?) -> Void) throws {
            active = true; self.exit = exit; self.failure = failure
        }
        func stop() { active = false; exit = nil; failure = nil }
    }

    static func run() -> Int {
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("\(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        var gesture = CleaningExitGesture()
        let event = CGEvent(source: nil)!
        for type in CleaningInputGuard.eventTypes {
            event.flags = []
            event.setIntegerValueField(.keyboardEventKeycode, value: 0)
            check(CleaningInputGuard.route(type: type, event: event, gesture: &gesture, at: 0) == .blocked,
                  "cleaning drops keyboard, pointer and media input: \(type.rawValue)")
        }
        let switchApp = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        switchApp.flags = .maskCommand
        check(CleaningInputGuard.route(type: .keyDown, event: switchApp, gesture: &gesture, at: 1) == .blocked,
              "Cmd Tab never reaches another application during cleaning")
        let forceQuit = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        forceQuit.flags = [.maskCommand, .maskAlternate]
        check(CleaningInputGuard.route(type: .keyDown, event: forceQuit, gesture: &gesture, at: 1) == .emergency,
              "system Force Quit is preserved and requests cleanup")
        let lock = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
        lock.flags = [.maskCommand, .maskControl]
        check(CleaningInputGuard.route(type: .keyDown, event: lock, gesture: &gesture, at: 1) == .emergency,
              "system screen lock is preserved for cleanup by the lock notification")
        check(CleaningInputGuard.route(type: .tapDisabledByTimeout, event: event, gesture: &gesture, at: 1) == .failed &&
              CleaningInputGuard.route(type: .tapDisabledByUserInput, event: event, gesture: &gesture, at: 1) == .failed,
              "disabled event taps fail closed rather than leaving a false cleaning state")
        var exitGesture = CleaningExitGesture()
        let escapeDown = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        escapeDown.flags = []
        _ = CleaningInputGuard.route(type: .keyDown, event: escapeDown, gesture: &exitGesture, at: 0)
        let escapeUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)!
        escapeUp.flags = []
        let released = CleaningInputGuard.route(type: .keyUp, event: escapeUp, gesture: &exitGesture, at: 3.1)
        check(released == .blocked && exitGesture.shouldExit, "native Esc routing consumes the release before requesting exit")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-cleaning-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = 0.0, idle = 0.0
        var wall = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        var outputs: [Output] = []
        let audio = FocusNoisePlayer { _ in let output = Output(); outputs.append(output); return output }
        func playing() -> Int { outputs.filter(\.isPlaying).count }
        var settings = AppSettings()
        settings.operatingSchedule.enabled = false
        settings.workMinutes = 1
        settings.soundEnabled = false; settings.prealertEnabled = false
        settings.checkForUpdatesAutomatically = false
        settings.focusNoiseEnabled = true; settings.focusNoiseRandom = true; settings.focusNoiseRandomCount = 2
        do {
            _ = try ConfigurationStore(directory: root).load(orCreate: settings)
            let model = AppModel(directory: root, focusNoise: audio, idleSeconds: { idle }, wallClock: { wall }, clock: { clock })
            defer { model.stop() }
            func advance(_ seconds: Double) { clock += seconds; wall.addTimeInterval(seconds); model.refresh() }
            model.restNow(); model.endBreak(); advance(10)
            let remaining = model.remaining, cycle = model.completedWorkSessions, mix = model.resolvedNoiseIDs
            let records = model.statistics.days, players = outputs.count
            let config = try Data(contentsOf: model.configuration.fileURL)
            check(cycle == 1 && playing() == 2, "diagnostic starts with an active second focus and an existing random mix")
            check(model.beginCleaning() && model.isCleaning && model.isPaused && playing() == 0,
                  "cleaning freezes running focus and every audio layer")
            idle = 301; advance(400)
            check(model.remaining == remaining && model.completedWorkSessions == cycle && model.statistics.days == records && !model.isAway,
                  "cleaning excludes focus, away and rest statistics and freezes the exact cycle")
            model.togglePause(); model.restart(); model.restNow(); model.previewBreak(); model.deferBreak()
            check(model.isCleaning && !model.isPreview && model.phase == .work && !model.canDefer && model.remaining == remaining,
                  "timer, preview, rest and delay actions cannot mutate an active cleaning session")
            idle = 0; model.endCleaning()
            check(!model.isPaused && model.remaining == remaining && model.resolvedNoiseIDs == mix && playing() == 2 && outputs.count == players,
                  "normal exit restores exact remaining time, cycle, random choices and original players")
            check((try Data(contentsOf: model.configuration.fileURL)) == config, "entering and leaving cleaning never rewrites preferences")
            model.togglePause(); _ = model.beginCleaning(); advance(10); model.endCleaning()
            check(model.isPaused && model.remaining == remaining && playing() == 0, "cleaning preserves an existing manual pause")
            model.togglePause(); _ = model.beginCleaning(); model.settings.workMinutes = 2; model.endCleaning()
            check(model.remaining == remaining, "plan edits during cleaning preserve the current snapshot deadline")
            model.restNow()
            check(!model.beginCleaning(), "real rest excludes cleaning")
            model.endBreak(); model.previewBreak()
            check(!model.beginCleaning(), "break preview excludes cleaning")
            model.endBreak()
            wall = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 11, minute: 59, second: 50))!
            model.settings.operatingSchedule = OperatingSchedule()
            model.restart(); let boundaryRemaining = model.remaining
            _ = model.beginCleaning(); let beforeLunch = model.statistics.days
            advance(60); model.endCleaning()
            check(model.isOutsideOperatingHours && model.isPaused && model.remaining == boundaryRemaining && model.statistics.days == beforeLunch,
                  "cleaning across lunch honors operating hours without accounting the hidden interval")
            check(playing() == 2 && model.beginCleaning() && playing() == 0,
                  "outside-hours standalone audio is also silenced by cleaning")
            model.endCleaning()

            let frame = NSRect(x: -10000, y: -10000, width: 320, height: 200)
            var screens = [CleaningScreen(id: 101, frame: frame), CleaningScreen(id: 102, frame: frame.offsetBy(dx: 400, dy: 0))]
            let originalOptions = NSApp.presentationOptions
            let originalSuspension = model.shortcuts.isSuspended
            let denied = CleaningWindowController(model: model, input: CleaningInputGuard(trusted: { false }), screens: { screens })
            do { try denied.start(); check(false, "missing permission is rejected") }
            catch CleaningProtectionError.accessibilityRequired {
                check(!model.isCleaning && denied.windowCount == 0 && NSApp.presentationOptions == originalOptions,
                      "permission denial leaves the timer, UI and system presentation untouched")
            }
            let secure = CleaningWindowController(model: model, input: CleaningInputGuard(trusted: { true }, secureInput: { true }), screens: { screens })
            do { try secure.start(); check(false, "secure input is rejected") }
            catch CleaningProtectionError.secureInput { check(!model.isCleaning && secure.windowCount == 0, "secure input never creates a misleading black lock screen") }
            let input = Input()
            let controller = CleaningWindowController(model: model, input: input, screens: { screens })
            defer { controller.stop(restoreApplication: false) }
            var interruptions = 0
            controller.onError = { _ in interruptions += 1 }
            try controller.start()
            check(controller.windowCount == 2 && input.active && model.isCleaning && model.shortcuts.isSuspended,
                  "two display descriptors share one cleaning session and one input guard")
            let sessionRemaining = model.remaining
            screens.removeLast(); controller.reconcileScreens()
            check(controller.windowCount == 1 && model.remaining == sessionRemaining && input.active,
                  "display removal changes windows without restarting the session")
            screens.append(CleaningScreen(id: 103, frame: frame.offsetBy(dx: 800, dy: 0))); controller.reconcileScreens()
            check(controller.windowCount == 2 && model.remaining == sessionRemaining, "new displays receive a black overlay during the same session")
            let overlays = NSApp.windows.filter { $0.isVisible && $0.title == model.text("屏幕键盘护理", "Screen & keyboard cleaning") }
            check(overlays.count == 2 && overlays.allSatisfy { $0.isOpaque && $0.backgroundColor == .black && $0.level == .screenSaver },
                  "cleaning overlays completely cover their displays independently of break transparency")
            input.exit?()
            check(!model.isCleaning && !input.active && controller.windowCount == 0 &&
                  NSApp.presentationOptions == originalOptions && model.shortcuts.isSuspended == originalSuspension,
                  "release-confirmed exit removes protection, windows and presentation changes")
            try controller.start(); input.failure?(.interrupted)
            check(!model.isCleaning && !input.active && controller.windowCount == 0 && interruptions == 1,
                  "input protection failure tears down the session before reporting an error")
            try controller.start(); input.failure?(nil)
            check(!model.isCleaning && interruptions == 1, "emergency system actions clean up without presenting a competing error dialog")
            try controller.start(); screens.removeAll(); controller.reconcileScreens()
            check(!model.isCleaning && !input.active && controller.windowCount == 0, "loss of every display exits cleaning safely")
            screens = [CleaningScreen(id: 101, frame: frame)]
            try controller.start(); model.willSleep()
            check(!model.isCleaning && !input.active && controller.windowCount == 0 && playing() == 0,
                  "sleep tears down cleaning without briefly restoring standalone noise")
            model.didWake()
            check(!model.isCleaning && playing() == 2, "wake restores ordinary operation without reentering cleaning")
            try controller.start(); model.setScreenLocked(true)
            check(!model.isCleaning && !input.active && playing() == 0, "system lock tears down cleaning and keeps audio silent")
            model.setScreenLocked(false)
            try controller.start(); model.stop()
            check(!model.isCleaning && !input.active && controller.windowCount == 0 && playing() == 0 && NSApp.presentationOptions == originalOptions,
                  "application shutdown cleans up a live session and releases audio")
        } catch { check(false, "cleaning lifecycle: \(error)") }
        return failures == 0 ? 0 : 1
    }
}

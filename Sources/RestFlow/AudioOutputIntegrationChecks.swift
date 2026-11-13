import AppKit
import CoreAudio
import RestFlowCore

@MainActor
enum AudioOutputIntegrationChecks {
    private final class Output: LoopAudioOutput {
        var volume: Float = 0
        var isPlaying = false
        func play() { isPlaying = true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }

    static func run() -> Int {
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("\(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        let speaker = AudioOutputMonitor.Output(id: 1, isExternal: false)
        let headphones = AudioOutputMonitor.Output(id: 2, isExternal: true)
        let usb = AudioOutputMonitor.Output(id: 3, isExternal: true)
        var snapshot: AudioOutputMonitor.Snapshot? = .init(output: headphones, aliveDevices: [1, 2, 3])
        let monitor = AudioOutputMonitor(readSnapshot: { snapshot })
        var changes: [Bool] = []
        monitor.start { changes.append($0) }
        monitor.refresh()
        check(changes.isEmpty, "audio monitor establishes a baseline without disabling playback")
        snapshot?.aliveDevices.remove(3); monitor.refresh()
        check(changes.isEmpty, "removing an unused device never interrupts the current output")
        snapshot = nil; monitor.refresh()
        check(changes.isEmpty, "failed Core Audio queries preserve the last known route")
        snapshot = .init(output: speaker, aliveDevices: [1, 2]); monitor.refresh()
        check(changes == [true], "AirPods leaving the route disable noise even while still paired")
        snapshot = .init(output: headphones, aliveDevices: [1, 2]); monitor.refresh()
        check(changes == [true, false], "reconnecting a route is a route change, not a playback enable")
        snapshot?.aliveDevices.remove(2); monitor.refresh()
        check(changes.last == true && changes.count == 3, "active output device removal disables noise before fallback arrives")
        monitor.refresh()
        check(changes.count == 3, "repeated device snapshots do not repeat disconnection actions")
        snapshot = .init(output: usb, aliveDevices: [1, 3]); monitor.refresh()
        check(changes.last == true, "switching away from an external route is handled conservatively")
        snapshot = .init(output: nil, aliveDevices: [1]); monitor.refresh()
        check(changes.last == true, "absence of a default output disables noise")
        snapshot = .init(output: speaker, aliveDevices: [1]); monitor.refresh()
        check(changes.last == false, "returning from no output rebuilds the route without enabling noise")
        monitor.stop()
        let stoppedCount = changes.count
        snapshot = .init(output: headphones, aliveDevices: [1, 2]); monitor.refresh()
        check(changes.count == stoppedCount, "stopping the monitor removes further route callbacks")
        snapshot = .init(output: .init(id: 1, isExternal: false, jackConnected: true), aliveDevices: [1])
        monitor.start { changes.append($0) }
        snapshot?.output?.jackConnected = false; monitor.refresh()
        check(changes.last == true && changes.count == stoppedCount + 1, "unplugging the headphone jack disables noise even with the same device ID")
        monitor.stop()

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-output-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = 0.0, idle = 0.0
        let calendar = Calendar.current
        func date(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: hour, minute: minute))!
        }
        var wall = date(12, 15)
        var outputs: [Output] = []
        let mixer = FocusNoisePlayer { _ in let output = Output(); outputs.append(output); return output }
        func playing() -> Int { outputs.filter(\.isPlaying).count }
        snapshot = .init(output: headphones, aliveDevices: [1, 2])
        var settings = AppSettings()
        settings.focusNoiseEnabled = true; settings.focusNoiseIDs = ["stream"]
        settings.soundEnabled = false; settings.prealertEnabled = false; settings.checkForUpdatesAutomatically = false
        do {
            _ = try ConfigurationStore(directory: root).load(orCreate: settings)
            let app = AppModel(directory: root, focusNoise: mixer, audioOutput: monitor, idleSeconds: { idle },
                               wallClock: { wall }, clock: { clock })
            defer { app.stop() }
            func advance(_ seconds: Double) { clock += seconds; wall.addTimeInterval(seconds); app.refresh() }
            check(app.isOutsideOperatingHours && app.isPaused && playing() == 1, "enabled noise starts independently at lunch without starting the timer")
            let remaining = app.remaining, records = app.statistics.days
            advance(20); idle = 301; app.refresh()
            check(playing() == 1 && app.remaining == remaining && app.statistics.days == records,
                  "outside-hours noise ignores focus idle detection and never creates timer statistics")
            app.willSleep(); check(playing() == 0, "sleep silences standalone noise even though the schedule already paused the timer")
            advance(1000); app.didWake()
            check(playing() == 1 && app.isPaused, "wake resumes standalone noise while keeping the outside-hours timer frozen")
            app.setScreenLocked(true); check(playing() == 0, "screen lock silences standalone noise")
            app.setScreenLocked(false); check(playing() == 1, "unlock restores eligible standalone noise")
            app.previewBreak(); check(playing() == 0, "outside-hours preview temporarily silences standalone noise")
            app.endBreak(); check(playing() == 1, "preview exit restores the standalone mix")
            app.toggleFocusNoise(); check(playing() == 0 && !app.isFocusNoiseEnabled, "standalone noise can be explicitly switched off outside hours")
            app.toggleFocusNoise(); check(playing() == 1 && app.isFocusNoiseEnabled, "standalone noise can be explicitly switched back on outside hours")
            idle = 0; wall = date(13, 30); app.refresh()
            check(!app.isOutsideOperatingHours && !app.isPaused && playing() == 1, "entering operating hours ties noise to running focus")
            app.togglePause(); check(playing() == 0, "inside hours manual plan pause also pauses noise")
            wall = date(18, 31); app.refresh()
            check(app.isOutsideOperatingHours && app.isPaused && playing() == 1, "leaving hours permits noise independently of a manual timer pause")
            wall = date(14); app.refresh()
            check(!app.isOutsideOperatingHours && app.isPaused && playing() == 0, "returning inside hours preserves manual pause and keeps noise silent")
            app.togglePause(); app.restNow()
            check(app.phase.isBreak && playing() == 0, "real rest inside hours releases independent audio too")
            app.endBreak(); check(playing() == 1, "new focus inside hours restores enabled noise")
            snapshot = .init(output: speaker, aliveDevices: [1]); app.refresh()
            check(!app.isFocusNoiseEnabled && !app.settings.focusNoiseEnabled && playing() == 0,
                  "active headphone removal immediately releases audio and unchecks the persistent switch")
            check((try? ConfigurationStore(directory: root).load(orCreate: settings).focusNoiseEnabled) == false,
                  "output disconnection persists disabled noise without modifying the selected mix")
            snapshot = .init(output: headphones, aliveDevices: [1, 2]); app.refresh()
            app.togglePause(); app.togglePause(); app.restart()
            check(!app.isFocusNoiseEnabled && playing() == 0, "reconnect, timer resume and restart never automatically re-enable disconnected noise")
            app.toggleFocusNoise()
            check(app.isFocusNoiseEnabled && playing() == 1 && app.settings.focusNoiseIDs == ["stream"],
                  "explicit re-enable resumes the same chosen mix on the current device")
            app.willSleep()
            snapshot = .init(output: speaker, aliveDevices: [1]); monitor.refresh(); app.didWake()
            check(!app.isFocusNoiseEnabled && playing() == 0, "headphones lost during sleep stay disabled after wake")
            app.toggleFocusNoise()
            snapshot = .init(output: headphones, aliveDevices: [1, 2]); monitor.refresh()
            var external = app.settings; external.volume = 0.42
            let data = try ConfigurationStore.encode(external)
            try data.write(to: app.configuration.fileURL, options: .atomic)
            snapshot = .init(output: speaker, aliveDevices: [1]); monitor.refresh()
            check(app.configurationError != nil && app.settings.focusNoiseEnabled && !app.isFocusNoiseEnabled && playing() == 0,
                  "disconnection remains silent and visibly off even if saving conflicts with external edits")
            check((try? Data(contentsOf: app.configuration.fileURL)) == data, "safety shutdown preserves an externally edited config")
            app.reloadConfiguration(force: true); app.refresh()
            check(!app.isFocusNoiseEnabled && playing() == 0, "reload of the same enabled preference cannot bypass the output-loss latch")
            app.toggleFocusNoise()
            check(app.isFocusNoiseEnabled && playing() == 1, "user can explicitly re-enable noise after resolving a save conflict")
            snapshot = .init(output: usb, aliveDevices: [1, 3]); app.refresh()
            check(app.isFocusNoiseEnabled && playing() == 1 && outputs.dropLast().allSatisfy { !$0.isPlaying },
                  "selecting a new external device from speakers rebuilds exactly one audio output")
            app.stop(); snapshot = .init(output: nil, aliveDevices: []); monitor.refresh()
            check(playing() == 0, "shutdown removes route monitoring and all audio output")
        } catch { check(false, "standalone output lifecycle: \(error)") }

        let system = AudioOutputMonitor()
        system.start { _ in }; system.refresh(); system.stop()
        check(AudioOutputMonitor.systemSnapshot() != nil, "Core Audio default-output discovery and native listener lifecycle are available")
        return failures
    }
}

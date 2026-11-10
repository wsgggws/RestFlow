import AppKit
import AVFoundation
import RestFlowCore

@MainActor
private final class RecordingLoopOutput: LoopAudioOutput {
    var volume: Float = 0
    var isPlaying = false
    var plays = 0, pauses = 0, stops = 0
    func play() { isPlaying = true; plays += 1 }
    func pause() { isPlaying = false; pauses += 1 }
    func stop() { isPlaying = false; stops += 1 }
}

@MainActor
enum AudioIntegrationChecks {
    static func run() -> Int {
        var failures = 0
        func check(_ result: Bool, _ message: String) {
            print("\(result ? "PASS" : "FAIL") \(message)"); if !result { failures += 1 }
        }
        var unique = Set<Data>()
        for noise in FocusNoise.allCases {
            do {
                guard let url = AudioAssets.noiseURL(noise.rawValue) else { throw ConfigurationError.invalid("Missing noise") }
                let file = try AVAudioFile(forReading: url)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                let samples = buffer.floatChannelData![0], count = Int(buffer.frameLength)
                var peak: Float = 0, energy: Double = 0
                for i in 0..<count { peak = max(peak, abs(samples[i])); energy += Double(samples[i]*samples[i]) }
                check(Double(count)/file.processingFormat.sampleRate == 16 && peak <= 0.451 && sqrt(energy/Double(count)) > 0.005,
                      "16-second noise decodes with signal and safe headroom: \(noise.rawValue)")
                unique.insert(try Data(contentsOf: url))
            } catch { check(false, "noise asset \(noise): \(error)") }
        }
        check(unique.count == 12, "twelve noise assets have distinct audio data")
        for id in AppSettings.systemSounds { check(FeedbackService.alertSound(id) != nil, "macOS alert is available: \(id)") }
        do {
            let backend = try AVAudioPlayer(contentsOf: AudioAssets.noiseURL("white")!)
            backend.volume = 0; backend.numberOfLoops = -1
            check(backend.play() && backend.isPlaying, "real AVAudioPlayer starts a silent infinite noise loop")
            backend.pause(); check(!backend.isPlaying, "real audio backend pauses"); backend.stop()
        } catch { check(false, "real audio backend: \(error)") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-noise-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = 0.0, idle = 0.0
        var wall = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        var outputs: [String: [RecordingLoopOutput]] = [:]
        let mixer = FocusNoisePlayer { url in
            let id = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "noise-", with: "")
            let output = RecordingLoopOutput(); outputs[id, default: []].append(output); return output
        }
        var s = AppSettings()
        s.operatingSchedule.enabled = false; s.soundEnabled = false; s.prealertEnabled = false
        s.checkForUpdatesAutomatically = false; s.workMinutes = 1; s.shortBreakSeconds = 5
        s.focusNoiseEnabled = true; s.focusNoiseIDs = ["white", "brown"]; s.focusNoiseRandom = true
        do {
            _ = try ConfigurationStore(directory: root).load(orCreate: s)
            let app = AppModel(directory: root, focusNoise: mixer, idleSeconds: { idle }, wallClock: { wall }, clock: { clock })
            defer { app.stop() }
            func advance(_ seconds: Double) { clock += seconds; wall.addTimeInterval(seconds); app.refresh() }
            func playingCount() -> Int { outputs.values.flatMap { $0 }.filter(\.isPlaying).count }
            let white = outputs["white"]!.last!, brown = outputs["brown"]!.last!
            let initialRandom = app.randomNoiseID
            check(playingCount() == 3 && !s.focusNoiseIDs.contains(initialRandom!), "fixed selections mix with one distinct random layer")
            check(abs(white.volume - 0.1) < 0.001, "combined mix divides volume across layers to avoid clipping")
            advance(1); app.settings.language = .english; app.refresh()
            check(app.randomNoiseID == initialRandom && white.plays == 1, "refresh and language changes retain the mix and random selection")
            app.settings.focusNoiseVolume = 0.6
            check(abs(white.volume-0.2) < 0.001 && white.plays == 1, "independent volume changes retain playheads")
            app.togglePause(); check(playingCount() == 0, "manual pause freezes every noise layer")
            app.togglePause(); check(playingCount() == 3 && white.plays == 2, "resume reuses the same players")
            app.willSleep(); check(playingCount() == 0, "sleep pauses focus noise")
            advance(1000); app.didWake()
            check(playingCount() == 3 && app.randomNoiseID == initialRandom, "wake restores the same focus mix without rerolling")
            app.settings.idleDetectionEnabled = true; idle = 61; app.refresh()
            check(app.isAway && playingCount() == 0, "idle focus cannot continue noise playback")
            idle = 0; advance(1)
            check(playingCount() == 3 && app.randomNoiseID == initialRandom, "short absence resumes original random noise")
            app.previewBreak()
            let playsBefore = white.plays, records = app.statistics.days
            check(playingCount() == 0, "preview never plays noise or rest music")
            advance(6)
            check(!app.isPreview && white.plays == playsBefore+1 && app.randomNoiseID == initialRandom && app.statistics.days == records,
                  "preview completion restores original focus mix and excludes statistics")
            app.settings.focusNoiseIDs = ["white"]
            check(white.isPlaying && brown.stops == 1 && outputs["white"]!.count == 1, "removing one layer leaves unchanged layers running")
            app.toggleFocusNoise(); check(playingCount() == 0, "menu/shortcut toggle immediately stops noise")
            app.toggleFocusNoise(); check(playingCount() == 2 && app.settings.focusNoiseIDs == ["white"], "toggle restores selected fixed and random mix")
            app.restNow(); check(playingCount() == 0 && app.phase.isBreak, "real rest releases all focus noise outputs")
            app.endBreak(); check(playingCount() == 2 && app.randomNoiseID != initialRandom, "new focus after Esc selects a different random layer")
            let beforeRestart = app.randomNoiseID
            app.restart(); check(app.randomNoiseID != beforeRestart && playingCount() == 2, "restart begins a new random focus segment")
            let naturalRandom = app.randomNoiseID
            advance(60); check(app.phase.isBreak && playingCount() == 0, "natural focus completion stops the mix")
            advance(6); check(app.phase == .work && playingCount() == 2 && app.randomNoiseID != naturalRandom, "natural break completion selects the next random layer")
            app.setScreenLocked(true); check(playingCount() == 0, "screen lock silences focus noise")
            app.setScreenLocked(false); check(playingCount() == 2, "unlock resumes eligible focus noise")
            let beforeAbsence = app.randomNoiseID
            idle = 301; advance(1); idle = 0; advance(1)
            check(playingCount() == 2 && app.randomNoiseID != beforeAbsence, "long absence starts a new random focus segment")
            app.settings.focusNoiseVolume = 0; check(playingCount() == 0, "zero noise volume silences the mixer")
            app.settings.focusNoiseVolume = 0.3
            wall = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12, minute: 15))!
            app.settings.operatingSchedule = OperatingSchedule()
            check(app.isOutsideOperatingHours && playingCount() == 0, "lunch cutoff silences focus noise")
            app.previewBreak(); check(playingCount() == 0, "outside-hours preview stays silent"); app.endBreak()
            app.settings.operatingSchedule.enabled = false
            let accepted = app.settings
            var external = accepted; external.volume = 0.41
            let data = try ConfigurationStore.encode(external)
            try data.write(to: app.configuration.fileURL, options: .atomic)
            app.toggleFocusNoise()
            check(app.settings == accepted && playingCount() == 2 && (try? Data(contentsOf: app.configuration.fileURL)) == data,
                  "failed toggle preserves playback and external configuration without recursion")
            app.reloadConfiguration(force: true)
            let source = AudioAssets.noiseURL("white")!
            try app.importAudio(from: source)
            let imported = app.soundURL!
            check(imported.path.hasPrefix(root.path) && FileManager.default.fileExists(atPath: imported.path), "alert import still makes an isolated managed copy")
            app.hideSelectedSound()
            check(app.settings.soundPath == nil && FileManager.default.fileExists(atPath: imported.path), "removing custom alert retains source file")
            app.settings.soundName = "Tink"; app.hideSelectedSound()
            check(app.settings.excludedSoundIDs.contains("Tink"), "system alert exclusions remain supported")
            let filesBefore = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("sounds").path)
            var edited = app.settings; edited.volume = 0.44
            let externalData = try ConfigurationStore.encode(edited)
            try externalData.write(to: app.configuration.fileURL, options: .atomic)
            do { try app.importAudio(from: source); check(false, "conflicting import rejected") }
            catch {
                let filesAfter = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("sounds").path)
                check(Set(filesBefore) == Set(filesAfter) && app.settings.soundPath == nil &&
                      (try? Data(contentsOf: app.configuration.fileURL)) == externalData,
                      "alert import conflict preserves external edits and removes only uncommitted copy")
            }
            app.reloadConfiguration(force: true)
            app.settings.focusNoiseIDs = FocusNoise.allCases.map(\.rawValue)
            check(playingCount() == 12 && Set(app.resolvedNoiseIDs).count == 12 && app.randomNoiseID == nil,
                  "all twelve fixed layers with Random never create duplicate players")
            let totalVolume = outputs.values.flatMap { $0 }.filter(\.isPlaying).reduce(Float(0)) { $0 + $1.volume }
            check(abs(totalVolume - 0.3) < 0.001, "all-layer mix stays within total volume budget")
            app.stop(); check(playingCount() == 0, "shutdown releases all audio outputs")
        } catch { check(false, "noise lifecycle: \(error)") }
        var loads = 0
        let failing = FocusNoisePlayer { _ in loads += 1; throw ConfigurationError.invalid("diagnostic decoder failure") }
        let error = failing.sync(ids: ["white"], volume: 0.3, running: true)
        _ = failing.sync(ids: ["white"], volume: 0.3, running: true)
        check(error != nil && loads == 1, "decoder failure is cached rather than retried every tick")
        failing.stop()
        return failures
    }
}

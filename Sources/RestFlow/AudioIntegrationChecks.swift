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
        var uniqueAudio = Set<Data>()
        for (id, url, looping) in AlertTone.allCases.filter({ $0 != .glass }).map({ ($0.rawValue, AudioAssets.alertURL($0.rawValue), false) }) +
            BackgroundTrack.allCases.map({ ($0.rawValue, AudioAssets.musicURL($0.rawValue), true) }) {
            do {
                guard let url else { throw ConfigurationError.invalid("Missing audio asset: \(id)") }
                let file = try AVAudioFile(forReading: url)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                let samples = buffer.floatChannelData![0]
                let count = Int(buffer.frameLength)
                let duration = Double(count) / file.processingFormat.sampleRate
                var peak: Float = 0, energy: Double = 0
                for i in 0..<count { peak = max(peak, abs(samples[i])); energy += Double(samples[i] * samples[i]) }
                let rms = sqrt(energy / Double(count))
                let seam = abs(samples[0] - samples[count - 1])
                check(count > 0 && peak < 0.5 && rms > 0.005 && (looping ? duration == 16 && seam < 0.025 : duration <= 3 && abs(samples[count - 1]) < 0.001),
                      "bundled \(looping ? "loop" : "alert") decodes, has safe headroom and smooth edges: \(id)")
                uniqueAudio.insert(try Data(contentsOf: url))
            } catch { check(false, "bundled audio \(id): \(error)") }
        }
        check(uniqueAudio.count == 23 && FeedbackService.alertSound("Glass") != nil, "eleven distinct original alerts plus twelve distinct loops and system Glass are available")

        do {
            let backend = try AVAudioPlayer(contentsOf: AudioAssets.musicURL("forest")!)
            backend.volume = 0; backend.numberOfLoops = -1
            check(backend.play() && backend.isPlaying && backend.numberOfLoops == -1, "real AVAudioPlayer backend starts a silent infinite loop")
            backend.pause()
            check(!backend.isPlaying, "real audio backend pauses")
            backend.stop()
        } catch { check(false, "real audio backend: \(error)") }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-audio-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = 0.0
        let origin = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        var wall = origin
        var outputs: [RecordingLoopOutput] = []
        var urls: [URL] = []
        let music = BackgroundMusicPlayer { url in
            let output = RecordingLoopOutput(); outputs.append(output); urls.append(url); return output
        }
        var settings = AppSettings()
        settings.operatingSchedule.enabled = false; settings.idleDetectionEnabled = false
        settings.soundEnabled = false; settings.prealertEnabled = false; settings.checkForUpdatesAutomatically = false
        settings.musicID = BackgroundTrack.matchedID; settings.visualID = BuiltinVisual.randomID
        do {
            _ = try ConfigurationStore(directory: root).load(orCreate: settings)
            let app = AppModel(directory: root, music: music, idleSeconds: { 0 }, wallClock: { wall }, clock: { clock })
            defer { app.stop() }
            func advance(_ seconds: Double) { clock += seconds; wall.addTimeInterval(seconds); app.refresh() }
            check(outputs.isEmpty, "focus never starts background music")
            app.restNow()
            let first = outputs.last!
            check(first.isPlaying && urls.last == AudioAssets.musicURL(app.breakContent.visual.rawValue), "rest starts one loop matching the resolved random scene")
            let resolved = app.resolvedMusicID
            advance(3); app.refresh(); app.settings.language = .english
            check(outputs.count == 1 && first.plays == 1 && app.resolvedMusicID == resolved,
                  "refresh, language changes and shared screen sync cannot restart or reroll a loop")
            app.settings.musicVolume = 0.18
            check(abs(first.volume - 0.18) < 0.001 && first.plays == 1, "music volume changes without restarting playback")
            app.togglePause()
            check(!first.isPlaying && first.pauses == 1, "manual pause freezes the current loop")
            app.togglePause()
            check(first.isPlaying && outputs.count == 1 && first.plays == 2, "resume reuses the same audio output and playhead")
            app.willSleep(); advance(1000); app.didWake()
            check(first.isPlaying && first.pauses == 2 && outputs.count == 1, "sleep pauses music and wake resumes it without creating a second loop")
            app.setScreenLocked(true)
            check(first.stops == 1 && !first.isPlaying && app.phase == .work, "lock ends real rest and releases its audio output")
            app.setScreenLocked(false)
            app.restNow(); let second = outputs.last!; app.endBreak()
            check(second.stops == 1 && !second.isPlaying, "Esc exit stops rest audio")
            app.previewBreak(); let preview = outputs.last!
            let records = app.statistics.days
            advance(31)
            check(!app.isPreview && preview.stops == 1 && records == app.statistics.days, "preview plays selected music and naturally stops without statistics")
            app.previewBreak(); let restarted = outputs.last!; app.restart()
            check(!restarted.isPlaying && restarted.stops == 1 && app.phase == .work, "restart stops preview audio and returns to focus")
            app.settings.visualID = "forest"; app.settings.musicID = AppSettings.randomSoundID
            app.restNow(); let random = app.resolvedMusicID
            advance(1); app.settings.language = .simplifiedChinese
            check(app.resolvedMusicID == random, "random background selection stays stable throughout a rest")
            app.settings.musicVolume = 0
            check(outputs.last?.isPlaying == false, "zero music volume releases playback")
            app.settings.musicVolume = 0.2; let beforeOutside = outputs.last!
            wall = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12, minute: 15))!
            app.settings.operatingSchedule = OperatingSchedule()
            check(!beforeOutside.isPlaying && app.isOutsideOperatingHours && app.phase == .work, "operating-hour cutoff stops all rest music")
            app.previewBreak(); let outsidePreview = outputs.last!
            check(outsidePreview.isPlaying && app.isPreview, "preview can play music outside operating hours")
            app.endBreak()
            check(!outsidePreview.isPlaying, "exiting outside-hours preview releases its loop")
            let source = AudioAssets.musicURL("rain")!
            try app.importAudio(from: source, background: true)
            let imported = app.musicURL!
            check(imported.path.hasPrefix(root.path) && (try? Data(contentsOf: imported)) == (try? Data(contentsOf: source)), "background import makes an isolated managed copy")
            app.selectMusic(AppSettings.noSoundID)
            check(app.settings.musicPath == nil && FileManager.default.fileExists(atPath: imported.path) && FileManager.default.fileExists(atPath: source.path), "choosing no music clears the reference and retains source audio")
            app.settings.soundName = "wood"; app.hideSelectedSound()
            let stored = try ConfigurationStore(directory: root).load(orCreate: settings)
            check(stored.excludedSoundIDs.contains("wood") && stored.soundName == AppSettings.noSoundID, "hiding an alert persists its exclusion and clears the current choice")
            app.settings.soundPath = imported.path; app.hideSelectedSound()
            check(app.settings.soundPath == nil && FileManager.default.fileExists(atPath: imported.path), "hiding custom alert audio preserves the imported file")
            let filesBefore = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("sounds").path)
            var external = app.settings; external.musicVolume = 0.41
            let data = try ConfigurationStore.encode(external)
            try data.write(to: app.configuration.fileURL, options: .atomic)
            do { try app.importAudio(from: source, background: true); check(false, "conflicted audio import rejected") }
            catch {
                let after = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("sounds").path)
                check(after == filesBefore && app.settings.musicPath == nil && (try? Data(contentsOf: app.configuration.fileURL)) == data,
                      "audio import conflict preserves external config and removes only the uncommitted new copy")
            }
            app.reloadConfiguration(force: true)
            app.settings.musicPath = "missing.wav"
            app.previewBreak()
            check(app.musicError != nil && outputs.last?.isPlaying == false && app.isPreview,
                  "invalid custom music shows an error and never prevents the break timer")
            app.settings.musicPath = nil; app.settings.musicID = "rain"
            let final = outputs.last!; app.stop()
            check(!final.isPlaying, "application shutdown releases background audio")
        } catch { check(false, "audio lifecycle checks: \(error)") }
        do {
            let directory = root.appendingPathComponent("natural")
            var naturalSettings = settings
            naturalSettings.workMinutes = 1; naturalSettings.shortBreakSeconds = 5
            _ = try ConfigurationStore(directory: directory).load(orCreate: naturalSettings)
            clock = 0; wall = origin
            let before = outputs.count
            let natural = AppModel(directory: directory, music: music, idleSeconds: { 0 }, wallClock: { wall }, clock: { clock })
            defer { natural.stop() }
            clock = 60; wall.addTimeInterval(60); natural.refresh()
            check(outputs.count == before + 1 && urls.last == AudioAssets.musicURL(natural.breakContent.visual.rawValue),
                  "natural break starts its newly resolved scene soundtrack without briefly playing the old one")
            let playing = outputs.last!
            clock += 6; wall.addTimeInterval(6); natural.refresh()
            check(natural.phase == .work && playing.stops == 1 && !playing.isPlaying, "natural rest completion stops looping audio")
        } catch { check(false, "natural music lifecycle: \(error)") }
        var loads = 0
        let failing = BackgroundMusicPlayer { _ in loads += 1; throw ConfigurationError.invalid("diagnostic decoder failure") }
        let badURL = URL(fileURLWithPath: "/tmp/diagnostic-bad-audio.wav")
        let firstError = failing.sync(url: badURL, volume: 0.3, running: true)
        _ = failing.sync(url: badURL, volume: 0.3, running: true)
        check(firstError != nil && loads == 1, "decoder failure is reported once without retrying every timer refresh")
        failing.stop()
        return failures
    }
}

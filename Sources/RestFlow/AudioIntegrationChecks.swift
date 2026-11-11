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
        var assetRMS: [String: Double] = [:]
        for noise in FocusNoise.allCases {
            do {
                guard let url = AudioAssets.noiseURL(noise.rawValue) else { throw ConfigurationError.invalid("Missing noise") }
                let file = try AVAudioFile(forReading: url)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                let count = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
                let recorded = ![FocusNoise.stream, .night, .keyboard].contains(noise)
                let duration = Double(count)/file.processingFormat.sampleRate
                var peak: Float = 0, energy = 0.0, quietWindows = 0
                for channel in 0..<channels {
                    let samples = buffer.floatChannelData![channel]
                    var windowEnergy = 0.0
                    let window = Int(file.processingFormat.sampleRate / 10)
                    for i in 0..<count {
                        peak = max(peak, abs(samples[i])); energy += Double(samples[i]*samples[i])
                        windowEnergy += Double(samples[i]*samples[i])
                        if (i+1) % window == 0 {
                            if sqrt(windowEnergy/Double(window)) < 0.02 { quietWindows += 1 }
                            windowEnergy = 0
                        }
                    }
                    // Broadband audio naturally has large adjacent sample differences.
                    // Detect a seam click relative to the local 10 ms derivative energy.
                    let edge = min(count/2, Int(buffer.format.sampleRate/100))
                    var derivativeEnergy = 0.0
                    for i in 1..<edge {
                        for offset in [0, count-edge] {
                            let delta = Double(samples[offset+i]-samples[offset+i-1])
                            derivativeEnergy += delta*delta
                        }
                    }
                    let localDerivative = sqrt(derivativeEnergy/Double(2*(edge-1)))
                    check(Double(abs(samples[0]-samples[count-1])) <= 5*localDerivative + 1/32768,
                          "loop boundary stays within local waveform variation: \(noise.rawValue), channel \(channel)")
                }
                let rms = sqrt(energy/Double(count*channels))
                assetRMS[noise.rawValue] = rms
                check(peak <= 0.921 && rms > 0.015 && rms <= 0.25 &&
                      (recorded ? ((18...48).contains(duration) && channels == 2 && buffer.format.sampleRate == 44100) : duration == 16),
                      "soundscape preserves headroom and expected format: \(noise.rawValue) (\(duration)s, RMS=\(rms), peak=\(peak))")
                if noise == .thunder {
                    var openingPeak: Float = 0, openingEnergy = 0.0
                    let openingFrames = Int(buffer.format.sampleRate * 0.3)
                    for channel in 0..<channels {
                        let samples = buffer.floatChannelData![channel]
                        for i in 0..<openingFrames {
                            openingPeak = max(openingPeak, abs(samples[i]))
                            openingEnergy += Double(samples[i]*samples[i])
                        }
                    }
                    check(openingPeak > 0.5 && sqrt(openingEnergy/Double(openingFrames*channels)) > 0.10,
                          "strong thunder begins within the first 300 ms without a quiet introduction")
                    check(Double(peak)/rms > 4 && rms >= 0.10,
                          "thunder preserves a sharp crack and an audible rolling body")
                }
                if noise == .keyboard { check(quietWindows >= 10, "mechanical typing retains pauses between phrases") }
                unique.insert(try Data(contentsOf: url))
            } catch { check(false, "noise asset \(noise): \(error)") }
        }
        check(unique.count == 12, "twelve soundscape assets have distinct audio data")
        for id in AppSettings.systemSounds { check(FeedbackService.alertSound(id) != nil, "macOS alert is available: \(id)") }
        do {
            func render(_ ids: [String], volume: Double) throws -> (rms: Double, peak: Float) {
                let graph = try NoiseAudioGraph(offline: true)
                let player = FocusNoisePlayer(graph: graph)
                defer { player.stop() }
                if let error = player.sync(ids: ids, volume: volume, running: true) { throw ConfigurationError.invalid(error) }
                let buffer = AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: 4096)!
                var frames = 0, energy = 0.0, peak: Float = 0
                for _ in 0..<540 {
                    if try graph.engine.renderOffline(4096, to: buffer) == .success {
                        for channel in 0..<2 {
                            let samples = buffer.floatChannelData![channel]
                            for index in 0..<Int(buffer.frameLength) { energy += Double(samples[index]*samples[index]); peak = max(peak, abs(samples[index])) }
                        }
                        frames += Int(buffer.frameLength)
                    }
                }
                guard frames > 44100*49 else { throw ConfigurationError.invalid("Offline graph did not render a complete loop") }
                return (sqrt(energy/Double(frames*2)), peak)
            }
            let single = try render(["lightRain"], volume: 1)
            check(single.peak <= 1 && (0.62...0.71).contains(single.rms / (assetRMS["lightRain"] ?? 1)),
                  "stereo recording gets the same two-thirds master gain as mono (RMS=\(single.rms))")
            let half = try render(["lightRain"], volume: 0.25)
            check((0.45...0.60).contains(half.rms/single.rms), "quarter slider provides roughly half amplitude for a more responsive control")
            let reference = try render(["stream"], volume: 1)
            check((0.62...0.71).contains(reference.rms / (assetRMS["stream"] ?? 1)), "mono recording retains the same two-thirds master gain (RMS=\(reference.rms))")
            let three = try render(["lightRain", "fire", "aircraft"], volume: 1)
            let all = try render(FocusNoise.allCases.map(\.rawValue), volume: 1)
            check(three.rms >= single.rms*0.80 && all.rms >= single.rms*0.80,
                  "three and twelve layers remain audible (RMS=\(three.rms), \(all.rms))")
            // The system limiter can overshoot by a fraction of one 16-bit PCM step.
            check(three.peak <= 1.00004 && all.peak <= 1.00004, "real peak limiter keeps multi-layer output within digital bounds (peaks=\(three.peak), \(all.peak))")
            let graph = try NoiseAudioGraph(offline: true)
            let enginePlayer = FocusNoisePlayer(graph: graph)
            _ = enginePlayer.sync(ids: ["aircraft"], volume: 0.3, running: true)
            check(graph.engine.isRunning, "real focus engine starts")
            _ = enginePlayer.sync(ids: ["aircraft"], volume: 0.3, running: false)
            check(!graph.engine.isRunning, "no active layer suspends the shared engine")
            _ = enginePlayer.sync(ids: ["aircraft"], volume: 0.3, running: true)
            check(graph.engine.isRunning, "shared engine resumes paused layers")
            _ = enginePlayer.sync(ids: ["aircraft", "keyboard"], volume: 0.3, running: true)
            check(graph.engine.isRunning, "adding a real layer keeps the audio graph running")
            _ = enginePlayer.sync(ids: ["keyboard"], volume: 0.3, running: true)
            check(graph.engine.isRunning, "removing a real layer keeps the remaining layer running")
            enginePlayer.stop(); check(!graph.engine.isRunning, "stopping releases real engine playback")
        } catch { check(false, "real focus audio graph: \(error)") }
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
        s.focusNoiseEnabled = true; s.focusNoiseIDs = ["lightRain", "aircraft"]
        do {
            _ = try ConfigurationStore(directory: root).load(orCreate: s)
            let app = AppModel(directory: root, focusNoise: mixer, idleSeconds: { idle }, wallClock: { wall }, clock: { clock })
            defer { app.stop() }
            func advance(_ seconds: Double) { clock += seconds; wall.addTimeInterval(seconds); app.refresh() }
            func playingCount() -> Int { outputs.values.flatMap { $0 }.filter(\.isPlaying).count }
            let windowRain = outputs["lightRain"]!.last!, aircraft = outputs["aircraft"]!.last!
            check(playingCount() == 2 && app.randomNoiseIDs.isEmpty, "manual selections play exactly two layers")
            check(abs(windowRain.volume - Float((2.0/3.0)*sqrt(0.3 / 2))) < 0.001, "equal-power mix applies the one-third amplitude reduction")
            advance(1); app.settings.language = .english; app.refresh()
            check(windowRain.plays == 1, "refresh and language changes retain manual playheads")
            app.settings.focusNoiseVolume = 0.6
            check(abs(windowRain.volume-Float((2.0/3.0)*sqrt(0.6 / 2))) < 0.001 && windowRain.plays == 1, "independent volume changes retain playheads")
            app.togglePause(); check(playingCount() == 0, "manual pause freezes every noise layer")
            app.togglePause(); check(playingCount() == 2 && windowRain.plays == 2, "resume reuses the same players")
            app.willSleep(); check(playingCount() == 0, "sleep pauses focus noise")
            advance(1000); app.didWake()
            check(playingCount() == 2 && outputs["lightRain"]!.count == 1, "wake restores focus mix without recreating layers")
            app.settings.idleDetectionEnabled = true; idle = 61; app.refresh()
            check(app.isAway && playingCount() == 0, "idle focus cannot continue noise playback")
            idle = 0; advance(1)
            check(playingCount() == 2, "short absence resumes original mix")
            app.previewBreak()
            let playsBefore = windowRain.plays, records = app.statistics.days
            check(playingCount() == 0, "preview never plays focus noise")
            advance(6)
            check(!app.isPreview && windowRain.plays == playsBefore+1 && app.statistics.days == records,
                  "preview completion restores focus playheads and excludes statistics")
            app.settings.focusNoiseIDs = ["lightRain"]
            check(windowRain.isPlaying && aircraft.stops == 1 && outputs["lightRain"]!.count == 1, "removing a layer leaves unchanged layers running")
            app.toggleFocusNoise(); check(playingCount() == 0, "menu/shortcut toggle immediately stops noise")
            app.toggleFocusNoise(); check(playingCount() == 1 && app.settings.focusNoiseIDs == ["lightRain"], "toggle restores selected manual mix")
            app.settings.selectRandomFocusNoise(true)
            check(app.settings.focusNoiseIDs.isEmpty && playingCount() == 1, "selecting Random immediately clears manual choices and starts one random layer")
            app.settings.focusNoiseRandomCount = 3
            let initialRandom = app.randomNoiseIDs
            check(initialRandom.count == 3 && Set(initialRandom).count == 3 && playingCount() == 3, "random mix count immediately selects three distinct layers")
            app.refresh(); app.settings.language = .simplifiedChinese
            check(app.randomNoiseIDs == initialRandom, "random mix is stable across refresh and language changes")
            app.togglePause(); app.togglePause(); app.previewBreak(); app.endBreak()
            check(app.randomNoiseIDs == initialRandom && playingCount() == 3, "pause and preview retain the same random mix")
            app.restNow(); check(playingCount() == 0 && app.phase.isBreak, "real rest releases all focus noise outputs")
            app.endBreak(); check(playingCount() == 3 && Set(app.randomNoiseIDs).isDisjoint(with: initialRandom), "new focus after Esc chooses a fresh random mix")
            let beforeRestart = app.randomNoiseIDs
            app.restart(); check(app.randomNoiseIDs != beforeRestart && playingCount() == 3, "restart begins a new random focus mix")
            let naturalRandom = app.randomNoiseIDs
            advance(60); check(app.phase.isBreak && playingCount() == 0, "natural focus completion stops the mix")
            advance(6); check(app.phase == .work && playingCount() == 3 && app.randomNoiseIDs != naturalRandom, "natural rest completion selects the next random mix")
            app.setScreenLocked(true); check(playingCount() == 0, "screen lock silences focus noise")
            app.setScreenLocked(false); check(playingCount() == 3, "unlock resumes eligible focus noise")
            let beforeAbsence = app.randomNoiseIDs
            idle = 301; advance(1); idle = 0; advance(1)
            check(playingCount() == 3 && app.randomNoiseIDs != beforeAbsence, "long absence starts a new random focus mix")
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
            let acceptedMix = app.resolvedNoiseIDs
            app.rerollFocusNoise()
            check(app.settings == accepted && app.resolvedNoiseIDs == acceptedMix,
                  "failed submenu random save preserves the current random draw")
            app.toggleFocusNoiseSelection(.stream)
            check(app.settings == accepted && app.resolvedNoiseIDs == acceptedMix,
                  "failed submenu selection preserves settings and current mix")
            app.settings.selectRandomFocusNoise(false)
            check(app.settings == accepted && playingCount() == 3 && (try? Data(contentsOf: app.configuration.fileURL)) == data,
                  "failed random toggle preserves mix and external configuration")
            app.reloadConfiguration(force: true)
            app.settings.selectRandomFocusNoise(false)
            check(app.settings.focusNoiseIDs.isEmpty && !app.settings.focusNoiseEnabled && playingCount() == 0,
                  "turning Random off leaves manual choices empty and stops playback")
            app.settings.focusNoiseIDs = ["keyboard"]; app.toggleFocusNoise()
            check(playingCount() == 1 && app.randomNoiseIDs.isEmpty, "manual mode starts only newly selected choices")
            let source = AudioAssets.noiseURL("lightRain")!
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
            app.settings.selectRandomFocusNoise(true); app.settings.focusNoiseRandomCount = 12
            check(playingCount() == 12 && Set(app.resolvedNoiseIDs).count == 12,
                  "random count twelve creates twelve distinct players")
            let totalPower = outputs.values.flatMap { $0 }.filter(\.isPlaying).reduce(Float(0)) { $0 + $1.volume * $1.volume }
            check(abs(totalPower - 0.3*4/9) < 0.001, "all-layer mix retains the reduced power budget")
            app.stop(); check(playingCount() == 0, "shutdown releases all audio outputs")
        } catch { check(false, "noise lifecycle: \(error)") }
        var loads = 0
        let failing = FocusNoisePlayer { _ in loads += 1; throw ConfigurationError.invalid("diagnostic decoder failure") }
        let error = failing.sync(ids: ["lightRain"], volume: 0.3, running: true)
        _ = failing.sync(ids: ["lightRain"], volume: 0.3, running: true)
        check(error != nil && loads == 1, "decoder failure is cached rather than retried every tick")
        failing.stop()
        return failures
    }
}

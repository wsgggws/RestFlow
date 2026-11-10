import Foundation
import RestFlowCore

func audioChecks() -> [(String, () -> Void)] {
    [
        ("audio catalogs contain twelve system alerts and twelve disabled-by-default soundscapes", {
            expectEqual(AlertTone.allCases.count, 12)
            expectEqual(AppSettings.systemSounds, AppSettings.alertSoundIDs)
            expectEqual(Set(FocusNoise.allCases.map(\.rawValue)).count, 12)
            let s = AppSettings()
            expectEqual(s.focusNoiseEnabled, false)
            expectEqual(s.focusNoiseIDs, [])
            expectEqual(s.focusNoiseRandom, false)
        }),
        ("retired audio migrates without enabling noise or removing custom references", {
            do {
                let data = Data(#"{"soundName":"wood","soundPath":"sounds/原音.wav","volume":0.27,"excludedSoundIDs":["dew","Ping"],"musicID":"rain","musicPath":"sounds/old.wav","musicVolume":0.5}"#.utf8)
                let s = try ConfigurationStore.decode(data)
                expectEqual(s.soundName, "Glass")
                expectEqual(s.soundPath, "sounds/原音.wav")
                expectEqual(s.volume, 0.27)
                expectEqual(s.excludedSoundIDs, ["Ping"])
                expectEqual(s.focusNoiseEnabled, false)
                let encoded = String(decoding: try ConfigurationStore.encode(s), as: UTF8.self)
                expectEqual(encoded.contains("music"), false)
                let hiddenGlass = try ConfigurationStore.decode(Data(#"{"soundName":"wood","excludedSoundIDs":["Glass"]}"#.utf8))
                expectEqual(hiddenGlass.soundName, AppSettings.noSoundID)
                expectEqual(hiddenGlass.excludedSoundIDs, ["Glass"])
                for name in AppSettings.systemSounds {
                    let loaded = try ConfigurationStore.decode(Data("{\"soundName\":\"\(name)\"}".utf8))
                    expectEqual(loaded.soundName, name)
                }
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("legacy noise IDs migrate to concrete scenes and random mode clears manual selections", {
            do {
                let raw = #"{"focusNoiseEnabled":true,"focusNoiseIDs":["white","pink","brown","lightRain"],"focusNoiseVolume":0.72}"#
                let s = try ConfigurationStore.decode(Data(raw.utf8))
                expectEqual(s.focusNoiseIDs, ["lightRain", "train", "aircraft"])
                expectEqual(s.focusNoiseEnabled, true)
                expectEqual(s.focusNoiseVolume, 0.72)
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(s)), s)
                let legacyRandom = try ConfigurationStore.decode(Data(#"{"focusNoiseRandom":true,"focusNoiseIDs":["brown","fire"]}"#.utf8))
                expectEqual(legacyRandom.focusNoiseIDs, [])
                expectEqual(legacyRandom.focusNoiseRandomCount, 1)
                expectEqual(Set(FocusNoise.allCases.map { $0.title(in: .simplifiedChinese) }).count, 12)
                expectEqual(Set(FocusNoise.allCases.map { $0.title(in: .english) }).count, 12)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("hidden system sounds leave random pool and empty libraries remain silent", {
            var s = AppSettings()
            s.hideSound("Glass"); s.soundName = AppSettings.randomSoundID
            expectEqual(s.selectedSound { $0.first! }, "Tink")
            for tone in AlertTone.allCases { s.hideSound(tone.rawValue) }
            expectEqual(s.hasSound, false)
            expectEqual(s.selectedSound { _ in fatalError("Empty pools cannot be sampled") }, AppSettings.noSoundID)
            s.soundPath = "sounds/custom.wav"
            expectEqual(s.hasSound, true)
        }),
        ("random mixing draws the requested unique count and avoids the previous set", {
            var s = AppSettings()
            s.focusNoiseRandom = true
            expectEqual(s.randomFocusNoises(avoiding: ["lightRain"], choose: { $0.first! }), ["train"])
            s.focusNoiseRandomCount = 3
            expectEqual(s.randomFocusNoises(avoiding: ["lightRain", "train", "aircraft"], choose: { $0.first! }), ["ocean", "wind", "stream"])
            s.focusNoiseRandomCount = 11
            let previous = Array(FocusNoise.allCases.dropLast().map(\.rawValue))
            let next = s.randomFocusNoises(avoiding: previous, choose: { $0.first! })
            expectEqual(Set(next).count, 11)
            expectEqual(Set(next) == Set(previous), false)
            s.focusNoiseRandomCount = 12
            expectEqual(Set(s.randomFocusNoises(avoiding: previous)).count, 12)
            s.focusNoiseRandom = false
            expectEqual(s.randomFocusNoises(), [])
        }),
        ("random selector clears manual choices on entry and leaves them empty on exit", {
            var s = AppSettings()
            s.focusNoiseEnabled = true; s.focusNoiseIDs = ["keyboard", "fire"]
            s.selectRandomFocusNoise(true)
            expectEqual(s.focusNoiseIDs, [])
            expectEqual(s.focusNoiseRandom && s.focusNoiseEnabled, true)
            s.selectRandomFocusNoise(false)
            expectEqual(s.focusNoiseIDs, [])
            expectEqual(s.focusNoiseRandom || s.focusNoiseEnabled, false)
        }),
        ("menu toggle defaults to random and preserves a chosen mix on disable", {
            var s = AppSettings()
            s.toggleFocusNoise()
            expectEqual(s.focusNoiseEnabled && s.focusNoiseRandom, true)
            s.focusNoiseIDs = ["lightRain"]
            s.toggleFocusNoise()
            expectEqual(s.focusNoiseEnabled, false)
            expectEqual(s.focusNoiseIDs, ["lightRain"])
            s.toggleFocusNoise()
            expectEqual(s.focusNoiseIDs, ["lightRain"])
        }),
        ("focus audio settings round-trip and reject invalid layers volumes and duplicate shortcuts", {
            do {
                var s = AppSettings()
                s.focusNoiseEnabled = true; s.focusNoiseIDs = ["aircraft", "fire"]
                s.focusNoiseRandomCount = 3; s.focusNoiseVolume = 0.22
                s.focusNoiseShortcut = KeyboardShortcut(keyCode: 45, modifiers: 6144)
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(s)), s)
                for raw in [#"{"focusNoiseRandomCount":0}"#, #"{"focusNoiseRandomCount":13}"#, #"{"focusNoiseVolume":1.1}"#, #"{"focusNoiseIDs":["bad"]}"#, #"{"focusNoiseRandom":true,"focusNoiseIDs":["bad"]}"#,
                            #"{"focusNoiseIDs":["lightRain","lightRain"]}"#, #"{"focusNoisePath":"file.wav"}"#,
                            #"{"pauseShortcut":{"keyCode":45,"modifiers":6144},"focusNoiseShortcut":{"keyCode":45,"modifiers":6144}}"#] {
                    do { _ = try ConfigurationStore.decode(Data(raw.utf8)); expectEqual("accepted", "rejected") } catch { }
                }
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("focus noise never creates rest prealerts or full-screen content", {
            var s = AppSettings()
            s.shortMessageID = ReminderMessage.noneID; s.visualID = BuiltinVisual.noneID
            s.soundName = AppSettings.noSoundID; s.focusNoiseEnabled = true; s.focusNoiseIDs = ["lightRain"]
            expectEqual(s.showsBreakScreen(for: .shortBreak), false)
            expectEqual(s.shouldPrealert(for: .shortBreak), false)
        })
    ]
}

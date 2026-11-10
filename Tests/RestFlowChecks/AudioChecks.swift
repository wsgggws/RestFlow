import Foundation
import RestFlowCore

func audioChecks() -> [(String, () -> Void)] {
    [
        ("audio catalogs contain twelve system alerts and twelve disabled-by-default focus noises", {
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
        ("random focus noise adds a unique layer and avoids previous segment when possible", {
            var s = AppSettings()
            s.focusNoiseIDs = ["white", "pink"]; s.focusNoiseRandom = true
            expectEqual(s.randomFocusNoise(avoiding: "brown", choose: { $0.first! }), "lightRain")
            s.focusNoiseIDs = FocusNoise.allCases.dropLast().map(\.rawValue)
            expectEqual(s.randomFocusNoise(avoiding: "night"), "night")
            s.focusNoiseIDs = FocusNoise.allCases.map(\.rawValue)
            expectEqual(s.randomFocusNoise { _ in fatalError("All layers already selected") }, nil)
            s.focusNoiseRandom = false
            expectEqual(s.randomFocusNoise(), nil)
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
                s.focusNoiseEnabled = true; s.focusNoiseIDs = ["brown", "fire"]
                s.focusNoiseRandom = true; s.focusNoiseVolume = 0.22
                s.focusNoiseShortcut = KeyboardShortcut(keyCode: 45, modifiers: 6144)
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(s)), s)
                for raw in [#"{"focusNoiseVolume":1.1}"#, #"{"focusNoiseIDs":["bad"]}"#,
                            #"{"focusNoiseIDs":["white","white"]}"#, #"{"focusNoisePath":"file.wav"}"#,
                            #"{"pauseShortcut":{"keyCode":45,"modifiers":6144},"focusNoiseShortcut":{"keyCode":45,"modifiers":6144}}"#] {
                    do { _ = try ConfigurationStore.decode(Data(raw.utf8)); expectEqual("accepted", "rejected") } catch { }
                }
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("focus noise never creates rest prealerts or full-screen content", {
            var s = AppSettings()
            s.shortMessageID = ReminderMessage.noneID; s.visualID = BuiltinVisual.noneID
            s.soundName = AppSettings.noSoundID; s.focusNoiseEnabled = true; s.focusNoiseIDs = ["white"]
            expectEqual(s.showsBreakScreen(for: .shortBreak), false)
            expectEqual(s.shouldPrealert(for: .shortBreak), false)
        })
    ]
}

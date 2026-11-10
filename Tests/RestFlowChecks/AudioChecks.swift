import Foundation
import RestFlowCore

func audioChecks() -> [(String, () -> Void)] {
    [
        ("audio catalog has twelve alert choices and twelve scene soundtracks", {
            expectEqual(AlertTone.allCases.count, 12)
            expectEqual(AppSettings.systemSounds, ["Glass"])
            expectEqual(Set(BackgroundTrack.allCases.map(\.rawValue)), Set(BuiltinVisual.allCases.map(\.rawValue)))
            expectEqual(AppSettings().musicID, AppSettings.noSoundID)
            expectEqual(AppSettings().hasMusic, false)
        }),
        ("retired system sounds migrate to Glass without changing paths or volume", {
            do {
                for name in ["Tink", "Ping", "Purr", "Pop", "Blow"] {
                    let data = Data("{\"soundName\":\"\(name)\",\"volume\":0.27,\"soundPath\":\"sounds/原音.wav\"}".utf8)
                    let loaded = try ConfigurationStore.decode(data)
                    expectEqual(loaded.soundName, "Glass")
                    expectEqual(loaded.soundPath, "sounds/原音.wav")
                    expectEqual(loaded.volume, 0.27)
                }
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("hidden sounds leave random pool and empty sound libraries remain silent", {
            var s = AppSettings()
            expectEqual(s.hideSound("Glass"), true)
            expectEqual(s.soundName, AppSettings.noSoundID)
            expectEqual(s.hideSound("Glass"), false)
            s.soundName = AppSettings.randomSoundID
            let selected = s.selectedSound { candidates in
                expectEqual(candidates.contains("Glass"), false)
                return candidates.first!
            }
            expectEqual(selected, "dew")
            for tone in AlertTone.allCases { s.hideSound(tone.rawValue) }
            expectEqual(s.hasSound, false)
            expectEqual(s.selectedSound { _ in fatalError("Empty pools cannot be sampled") }, AppSettings.noSoundID)
            s.soundPath = "sounds/custom.wav"
            expectEqual(s.hasSound, true)
            s.excludedSoundIDs = []
            expectEqual(s.availableSounds.count, 12)
        }),
        ("matching music follows the resolved random scene and respects no visual or imports", {
            var s = AppSettings()
            s.musicID = BackgroundTrack.matchedID; s.visualID = BuiltinVisual.randomID
            let scene = BreakContent(settings: s, choose: { $0.last! }).visual
            expectEqual(s.resolveMusic(visual: scene), scene.rawValue)
            s.visualID = BuiltinVisual.noneID
            expectEqual(s.resolveMusic(visual: scene), AppSettings.noSoundID)
            expectEqual(s.hasMusic, false)
            s.visualID = "forest"; s.mediaPath = "my.gif"
            expectEqual(s.resolveMusic(visual: .forest), AppSettings.noSoundID)
            s.musicPath = "sounds/loop.wav"
            expectEqual(s.resolveMusic(visual: .forest), "__custom__")
            expectEqual(s.hasMusic, true)
        }),
        ("random music avoids previous track and fixed music remains independent of visuals", {
            var s = AppSettings()
            s.musicID = AppSettings.randomSoundID
            expectEqual(s.resolveMusic(visual: .forest, avoiding: "rings", choose: { $0.first! }), "orbit")
            s.musicID = "waves"; s.visualID = BuiltinVisual.noneID
            expectEqual(s.resolveMusic(visual: .forest), "waves")
            expectEqual(s.hasMusic, true)
            s.musicVolume = 0
            expectEqual(s.hasMusic, false)
        }),
        ("audio preferences round-trip with relative paths and reject invalid IDs and ranges", {
            do {
                var s = AppSettings()
                s.musicPath = "sounds/海浪 🎵.wav"; s.musicID = "rain"; s.musicVolume = 0.22
                s.hideSound("wood")
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(s)), s)
                let directory = URL(fileURLWithPath: "/tmp/restflow-audio")
                expectEqual(ConfigurationStore(directory: directory).resolve(s.musicPath)?.path, "/tmp/restflow-audio/sounds/海浪 🎵.wav")
                let invalid = [#"{"musicVolume":1.1}"#, #"{"musicID":"bad"}"#, #"{"musicPath":"https://example.org/a.wav"}"#,
                               #"{"excludedSoundIDs":["dew","dew"]}"#, #"{"soundName":"wood","excludedSoundIDs":["wood"]}"#]
                for raw in invalid {
                    do { _ = try ConfigurationStore.decode(Data(raw.utf8)); expectEqual("accepted", "rejected") } catch { }
                }
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("music-only breaks keep prealerts without creating fullscreen content", {
            var s = AppSettings()
            s.shortMessageID = ReminderMessage.noneID; s.visualID = BuiltinVisual.noneID
            s.soundName = AppSettings.noSoundID; s.musicID = "rain"
            expectEqual(s.showsBreakScreen(for: .shortBreak), false)
            expectEqual(s.shouldPrealert(for: .shortBreak), true)
            s.musicID = AppSettings.noSoundID
            expectEqual(s.shouldPrealert(for: .shortBreak), false)
        })
    ]
}

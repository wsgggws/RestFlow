import Foundation
import RestFlowCore

private func rejects(_ action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
    do {
        try action()
        failures += 1
        print("FAIL \(file):\(line): expected rejection")
    } catch {}
}

private func withStore(_ action: (ConfigurationStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-check-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try action(ConfigurationStore(directory: directory))
}

func configurationChecks() -> [(String, () -> Void)] {
    let cases: [(String, () throws -> Void)] = [
        ("documented example matches application defaults", {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Examples/config.json")
            expectEqual(try ConfigurationStore.decode(Data(contentsOf: url)), AppSettings())
        }),
        ("config defaults and partial file", {
            let settings = try ConfigurationStore.decode(Data(#"{"language":"en","showMenuBarTime":false}"#.utf8))
            expectEqual(settings.language, .english)
            expectEqual(settings.showMenuBarTime, false)
            expectEqual(settings.workMinutes, 25)
            expectEqual(settings.breakTransparency, 0)
            expectEqual(settings.checkForUpdatesAutomatically, true)
            expectEqual(settings.messages.count, 12)
        }),
        ("legacy artwork controls reset to opaque background; new transparency wins", {
            for field in ["visualOpacity", "visualGrayness"] {
                let settings = try ConfigurationStore.decode(Data("{\"\(field)\":0.5}".utf8))
                expectEqual(settings.breakTransparency, 0)
                let encoded = String(decoding: try ConfigurationStore.encode(settings), as: UTF8.self)
                expectEqual(encoded.contains(field), false)
                let modern = try ConfigurationStore.decode(Data("{\"\(field)\":0.8,\"breakTransparency\":0.3}".utf8))
                expectEqual(modern.breakTransparency, 0.3)
                rejects { _ = try ConfigurationStore.decode(Data("{\"\(field)\":2}".utf8)) }
            }
        }),
        ("legacy built-in citations migrate but custom text survives", {
            var settings = AppSettings()
            settings.messages[4].text = "致虚极，守静笃。——《道德经》第十六章"
            settings.messages[4].englishText = "Empty the mind; remain deeply still. — Dao De Jing, 16"
            let custom = ReminderMessage(id: "custom", text: "自定义——保留出处与符号 🌿")
            settings.messages.append(custom)
            let migrated = try ConfigurationStore.decode(ConfigurationStore.encode(settings))
            expectEqual(migrated.messages[4], ReminderMessage.defaults[4])
            expectEqual(migrated.messages.last, custom)
        }),
        ("shortcut settings round trip and reject duplicate or unmodified keys", {
            var settings = AppSettings()
            expectEqual(settings.pauseShortcut, nil)
            expectEqual(settings.launchAtLogin, false)
            settings.launchAtLogin = true
            settings.pauseShortcut = KeyboardShortcut(keyCode: 35, modifiers: 4096 | 2048)
            settings.restartShortcut = KeyboardShortcut(keyCode: 15, modifiers: 4096 | 2048)
            settings.restNowShortcut = KeyboardShortcut(keyCode: 11, modifiers: 4096 | 2048)
            expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), settings)
            settings.restNowShortcut = settings.pauseShortcut
            rejects { try settings.validate() }
            for key in [KeyboardShortcut(keyCode: 35, modifiers: 0), KeyboardShortcut(keyCode: 35, modifiers: 512),
                        KeyboardShortcut(keyCode: 53, modifiers: 256), KeyboardShortcut(keyCode: 200, modifiers: 256),
                        KeyboardShortcut(keyCode: 55, modifiers: 256), KeyboardShortcut(keyCode: 35, modifiers: 1)] {
                rejects { try key.validate() }
            }
        }),
        ("failed integration validation preserves external config", {
            try withStore { store in
                let initial = try store.load()
                var external = initial
                external.launchAtLogin = true
                try ConfigurationStore.encode(external).write(to: store.fileURL, options: .atomic)
                rejects { _ = try store.reload(validate: { _ in throw ConfigurationError.invalid("integration conflict") }) }
                rejects { try store.save(initial) }
                expectEqual(try store.reload(force: true), external)
            }
        }),
        ("new default plan reaches long break after two focus sessions", {
            let settings = AppSettings()
            expectEqual(settings.workMinutes, 25)
            expectEqual(settings.shortBreakSeconds, 30)
            expectEqual(settings.longBreakMinutes, 5)
            expectEqual(settings.cycles, 2)
            expectEqual(settings.plan, SessionPlan())
            var engine = SessionEngine(plan: settings.plan, now: 0)
            _ = engine.tick(at: 1500)
            expectEqual(engine.phase, .shortBreak)
            expectEqual(engine.remaining(at: 1500), 30)
            _ = engine.tick(at: 1530)
            _ = engine.tick(at: 3030)
            expectEqual(engine.phase, .longBreak)
            expectEqual(engine.remaining(at: 3030), 300)
        }),
        ("random content remains stable across reads and follows language changes", {
            var settings = AppSettings()
            settings.shortMessageID = ReminderMessage.randomID
            settings.longMessageID = ReminderMessage.randomID
            settings.visualID = BuiltinVisual.randomID
            let first = BreakContent(settings: settings, choose: { $0.first! })
            let next = BreakContent(settings: settings, choose: { $0.last! })
            expectEqual(first.message(for: .shortBreak, settings: settings), settings.messages.first!.text)
            expectEqual(first.message(for: .longBreak, settings: settings), settings.messages.first!.text)
            expectEqual(first.visual, .rings)
            for _ in 0..<20 { expectEqual(first.message(for: .shortBreak, settings: settings), settings.messages.first!.text) }
            expectEqual(next.visual, .fireflies)
            expectEqual(next.message(for: .shortBreak, settings: settings), settings.messages.last!.text)
            settings.language = .english
            expectEqual(first.message(for: .shortBreak, settings: settings), settings.messages.first!.englishText!)
            try settings.validate()
            expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), settings)
        }),
        ("none and random selections distinguish short and long break visibility", {
            for short in [ReminderMessage.noneID, ReminderMessage.randomID, "eyes"] {
                for long in [ReminderMessage.noneID, ReminderMessage.randomID, "stretch"] {
                    for visual in [BuiltinVisual.noneID, BuiltinVisual.randomID, "rings"] {
                        var settings = AppSettings()
                        settings.shortMessageID = short
                        settings.longMessageID = long
                        settings.visualID = visual
                        let decoded = try ConfigurationStore.decode(ConfigurationStore.encode(settings))
                        expectEqual(decoded, settings)
                        let content = BreakContent(settings: decoded, choose: { $0.first! })
                        expectEqual(decoded.showsBreakScreen(for: .work), false)
                        for (phase, messageID) in [(SessionPhase.shortBreak, short), (.longBreak, long)] {
                            expectEqual(decoded.showsBreakScreen(for: phase), visual != BuiltinVisual.noneID || messageID != ReminderMessage.noneID)
                            expectEqual(content.message(for: phase, settings: decoded).isEmpty, messageID == ReminderMessage.noneID)
                        }
                    }
                }
            }
            var settings = AppSettings()
            settings.shortMessageID = ReminderMessage.noneID
            settings.visualID = BuiltinVisual.noneID
            settings.mediaPath = "media/custom.gif"
            expectEqual(settings.hasVisual, true)
            expectEqual(settings.showsBreakScreen(for: .shortBreak), true)
            settings.messages[0].id = ReminderMessage.noneID
            rejects { try settings.validate() }
        }),
        ("none sound and disabled sound stay silent with custom sound precedence", {
            var settings = AppSettings()
            settings.soundName = AppSettings.noSoundID
            expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), settings)
            expectEqual(settings.hasSound, false)
            settings.shortMessageID = ReminderMessage.noneID
            settings.visualID = BuiltinVisual.noneID
            expectEqual(settings.shouldPrealert(for: .shortBreak), false)
            expectEqual(settings.shouldPrealert(for: .longBreak), true)
            settings.soundPath = "sounds/custom.wav"
            expectEqual(settings.hasSound, true)
            expectEqual(settings.shouldPrealert(for: .shortBreak), true)
            settings.soundEnabled = false
            expectEqual(settings.hasSound, false)
            settings.soundEnabled = true
            settings.volume = 0
            expectEqual(settings.hasSound, false)
        }),
        ("message duplicate comparison respects whitespace, Unicode and translations", {
            var settings = AppSettings()
            settings.messages.append(ReminderMessage(id: "accent", text: "Café 💧"))
            expectEqual(settings.containsMessage(" \nCaf\u{301}e 💧 "), false)
            expectEqual(settings.containsMessage(" \nCafe\u{301}   💧 \t"), true)
            expectEqual(settings.containsMessage(" LOOK INTO THE DISTANCE.\nGive your eyes a rest. "), true)
            expectEqual(settings.containsMessage("看向远方，让眼睛休息一下。"), true)
            expectEqual(settings.containsMessage("Café ❤️"), false)
            expectEqual(settings.containsMessage("Cafe 💧"), false)
        }),
        ("message choices deduplicate legacy labels while preserving selected IDs and text", {
            var settings = AppSettings()
            settings.messages = [
                ReminderMessage(id: "first", text: " 喝水 💧 ", englishText: "Take a break"),
                ReminderMessage(id: "duplicate", text: "喝水   💧", englishText: "TAKE A\nBREAK"),
                ReminderMessage(id: "other", text: "走走 🚶", englishText: "Take a break"),
                ReminderMessage(id: "accent", text: "Café"),
                ReminderMessage(id: "equivalent", text: "Cafe\u{301}"),
            ]
            settings.shortMessageID = "duplicate"
            settings.longMessageID = "other"
            let original = settings
            expectEqual(settings.messageChoices().map(\.id), ["first", "other", "accent"])
            expectEqual(settings.messageChoices(selectedID: "duplicate").map(\.id), ["duplicate", "other", "accent"])
            expectEqual(settings, original)
            expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), original)
            settings.language = .english
            expectEqual(settings.messageChoices().map(\.id), ["first", "accent"])
            expectEqual(settings.messageChoices(selectedID: "other").map(\.id), ["other", "accent"])
            expectEqual(settings.messages.count, 5)
            expectEqual(settings.message(for: .shortBreak), "TAKE A\nBREAK")
        }),
        ("random reminder pool contains each visible message once", {
            var settings = AppSettings()
            settings.messages.append(ReminderMessage(id: "duplicate", text: "  看向远方，让眼睛休息一下。  "))
            settings.shortMessageID = ReminderMessage.randomID
            settings.longMessageID = ReminderMessage.randomID
            var draws = 0
            let content = BreakContent(settings: settings, choose: { ids in
                draws += 1
                expectEqual(ids.count, ReminderMessage.defaults.count)
                expectEqual(ids.contains("duplicate"), false)
                return ids.first!
            })
            expectEqual(draws, 2)
            expectEqual(content.shortMessageID, "eyes")
            expectEqual(content.longMessageID, "eyes")
        }),
        ("visual catalog validation and legacy media paths", {
            expectEqual(BuiltinVisual.allCases.count, 12)
            for visual in BuiltinVisual.allCases {
                var settings = AppSettings()
                settings.visualID = visual.rawValue
                let decoded = try ConfigurationStore.decode(ConfigurationStore.encode(settings))
                expectEqual(BreakContent(settings: decoded).visual, visual)
            }
            let legacy = try ConfigurationStore.decode(Data(#"{"mediaPath":"media/old.gif"}"#.utf8))
            expectEqual(legacy.mediaPath, "media/old.gif")
            expectEqual(legacy.visualID, "rings")
            rejects { _ = try ConfigurationStore.decode(Data(#"{"visualID":"missing"}"#.utf8)) }
            var settings = AppSettings()
            settings.messages[0].id = ReminderMessage.randomID
            rejects { try settings.validate() }
        }),
        ("all config fields round-trip with Unicode and paths", {
            var settings = AppSettings()
            settings.language = .english
            settings.showMenuBarTime = false
            settings.workMinutes = 31
            settings.shortBreakSeconds = 35
            settings.longBreakMinutes = 8
            settings.cycles = 3
            settings.prealertEnabled = false
            settings.warningSeconds = 11
            settings.soundEnabled = false
            settings.soundName = "Glass"
            settings.soundPath = "sounds/提醒 🎵.wav"
            settings.volume = 0.23
            settings.breakTransparency = 0.72
            settings.checkForUpdatesAutomatically = false
            settings.mediaPath = "media/休息.gif"
            settings.visualID = "waves"
            let message = ReminderMessage(id: "custom", text: "喝水 💧 \"quote\" \\ slash\n第二行 <> & * _ \t 𝄞")
            settings.messages.append(message)
            settings.shortMessageID = message.id
            settings.longMessageID = message.id
            expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), settings)
        }),
        ("relative paths independent of process working directory", {
            let base = URL(fileURLWithPath: "/tmp/restflow-path-check")
            let store = ConfigurationStore(directory: base)
            expectEqual(store.resolve("media/a b.gif")?.path, "/tmp/restflow-path-check/media/a b.gif")
            expectEqual(store.resolve("./sounds/../tone.wav")?.path, "/tmp/restflow-path-check/tone.wav")
            expectEqual(store.resolve("/tmp/absolute.png")?.path, "/tmp/absolute.png")
            expectEqual(store.resolve("~/sounds/a.wav")?.path,
                        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("sounds/a.wav").path)
            expectEqual(store.resolve(nil), nil)
        }),
        ("message translations preserve user input", {
            var settings = AppSettings()
            settings.language = .english
            expectEqual(settings.message(for: .shortBreak), "Look into the distance. Give your eyes a rest.")
            let custom = ReminderMessage(id: "mine", text: "原文 🌿 \"\n\" \\ ❤️")
            settings.messages.append(custom)
            settings.shortMessageID = custom.id
            settings.longMessageID = custom.id
            expectEqual(settings.message(for: .shortBreak), custom.text)
            settings.language = .simplifiedChinese
            expectEqual(settings.message(for: .longBreak), custom.text)
        }),
        ("invalid configuration types and unknown keys rejected", {
            for json in [#"{"workMinutes":"25"}"#, #"{"workMinute":25}"#,
                         #"{"language":"fr"}"#, #"{"schemaVersion":99}"#,
                         #"{"cycles":0}"#, #"{"breakTransparency":1.01}"#, #"{"breakTransparency":-0.1}"#, #"{"checkForUpdatesAutomatically":"true"}"#, #"{"volume":2}"#, #"{"mediaPath":"https://example.com/a.gif"}"#] {
                rejects { _ = try ConfigurationStore.decode(Data(json.utf8)) }
            }
        }),
        ("message IDs and text validated", {
            var settings = AppSettings()
            settings.shortMessageID = "missing"
            rejects { try settings.validate() }
            settings = AppSettings()
            settings.messages.append(settings.messages[0])
            rejects { try settings.validate() }
            settings = AppSettings()
            settings.messages[0].text = " \n\t "
            rejects { try settings.validate() }
        }),
        ("store writes and detects external atomic replacement", {
            try withStore { store in
                let initial = try store.load()
                expectEqual(try store.reload(), nil)
                var changed = initial
                changed.language = .english
                try ConfigurationStore.encode(changed).write(to: store.fileURL, options: .atomic)
                expectEqual(try store.reload(), changed)
                expectEqual(try store.reload(), nil)
                changed.volume = 0.7
                try store.save(changed)
                expectEqual(try store.reload(force: true), changed)
            }
        }),
        ("invalid external edit cannot be overwritten by UI", {
            try withStore { store in
                let initial = try store.load()
                let invalid = Data("{broken".utf8)
                try invalid.write(to: store.fileURL, options: .atomic)
                rejects { _ = try store.reload() }
                rejects { try store.save(initial) }
                expectEqual(try Data(contentsOf: store.fileURL), invalid)
                expectEqual(try store.reload(), nil)
                try ConfigurationStore.encode(initial).write(to: store.fileURL, options: .atomic)
                expectEqual(try store.reload(), initial)
            }
        }),
        ("valid file edit wins a UI-save race", {
            try withStore { store in
                let initial = try store.load()
                var external = initial
                external.workMinutes = 42
                try ConfigurationStore.encode(external).write(to: store.fileURL, options: .atomic)
                rejects { try store.save(initial) }
                expectEqual(try store.reload(), external)
            }
        }),
        ("invalid startup file remains untouched", {
            try withStore { store in
                try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
                let bad = Data(#"{"cycles":999}"#.utf8)
                try bad.write(to: store.fileURL)
                rejects { _ = try store.load() }
                expectEqual(try Data(contentsOf: store.fileURL), bad)
                rejects { try store.save(AppSettings()) }
            }
        }),
        ("deleted config is not silently recreated by UI", {
            try withStore { store in
                let initial = try store.load()
                try FileManager.default.removeItem(at: store.fileURL)
                rejects { try store.save(initial) }
                expectEqual(FileManager.default.fileExists(atPath: store.fileURL.path), false)
            }
        }),
    ]
    return cases.map { name, test in
        (name, {
            do { try test() }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        })
    }
}

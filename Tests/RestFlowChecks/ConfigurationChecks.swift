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
            expectEqual(settings.visualOpacity, 1)
            expectEqual(settings.checkForUpdatesAutomatically, true)
            expectEqual(settings.messages.count, 12)
        }),
        ("legacy grayness migrates to opacity without persisting legacy key", {
            let settings = try ConfigurationStore.decode(Data(#"{"visualGrayness":0.5}"#.utf8))
            expectEqual(settings.visualOpacity, 0.8)
            let encoded = String(decoding: try ConfigurationStore.encode(settings), as: UTF8.self)
            expectEqual(encoded.contains("visualGrayness"), false)
            expectEqual(try ConfigurationStore.decode(Data(#"{"visualGrayness":0.8,"visualOpacity":0.3}"#.utf8)).visualOpacity, 0.3)
            rejects { _ = try ConfigurationStore.decode(Data(#"{"visualGrayness":2}"#.utf8)) }
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
            settings.soundName = "Ping"
            settings.soundPath = "sounds/提醒 🎵.wav"
            settings.volume = 0.23
            settings.visualOpacity = 0.72
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
                         #"{"cycles":0}"#, #"{"visualOpacity":1.01}"#, #"{"visualOpacity":-0.1}"#, #"{"checkForUpdatesAutomatically":"true"}"#, #"{"volume":2}"#, #"{"mediaPath":"https://example.com/a.gif"}"#] {
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

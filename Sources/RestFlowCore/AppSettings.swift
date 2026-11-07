import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public func text(_ chinese: String, _ english: String) -> String {
        self == .english ? english : chinese
    }
}

public struct ReminderMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var englishText: String?

    public init(id: String = UUID().uuidString, text: String, englishText: String? = nil) {
        self.id = id
        self.text = text
        self.englishText = englishText
    }

    public func displayText(in language: AppLanguage) -> String {
        language == .english ? (englishText ?? text) : text
    }

    /// Compare menu labels without changing the user's original punctuation or emoji.
    public static func selectionKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static let randomID = "__random__"
    public static let noneID = "__none__"

    public static let defaults: [ReminderMessage] = [
        .init(id: "eyes", text: "看向远方，让眼睛休息一下。", englishText: "Look into the distance. Give your eyes a rest."),
        .init(id: "stretch", text: "站起来，伸个懒腰，喝一杯水。", englishText: "Stand up, stretch, and have some water."),
        .init(id: "breathe", text: "放松肩膀，慢慢呼吸。", englishText: "Relax your shoulders. Take a slow breath."),
        .init(id: "walk", text: "离开屏幕，走动一会儿 🌿", englishText: "Step away from the screen. Take a little walk 🌿"),
        .init(id: "stillness", text: "致虚极，守静笃。", englishText: "Empty the mind; remain deeply still."),
        .init(id: "water", text: "上善若水。", englishText: "The highest goodness is like water."),
        .init(id: "journey", text: "千里之行，始于足下。", englishText: "A journey of a thousand miles begins beneath your feet."),
        .init(id: "balance", text: "文武之道，一张一弛。", englishText: "The way of balance is to alternate tension and relaxation."),
        .init(id: "joy", text: "知之者不如好之者，好之者不如乐之者。", englishText: "Knowing is less than loving; loving is less than finding joy."),
        .init(id: "nature", text: "人法地，地法天，天法道，道法自然。", englishText: "Human follows earth, earth follows heaven, heaven follows the Way, and the Way follows nature."),
        .init(id: "learn", text: "三人行，必有我师焉。", englishText: "Among any three people walking together, there is someone I can learn from."),
        .init(id: "flow", text: "逝者如斯夫，不舍昼夜。", englishText: "It flows on like this, never ceasing day or night."),
    ]
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let noSoundID = "__none__"
    public var schemaVersion = 1
    public var language: AppLanguage = .simplifiedChinese
    public var showMenuBarTime = true
    public var checkForUpdatesAutomatically = true
    public var breakTransparency: Double = 0
    public var launchAtLogin = false
    public var pauseShortcut: KeyboardShortcut?
    public var restartShortcut: KeyboardShortcut?
    public var restNowShortcut: KeyboardShortcut?
    public var workMinutes: Double = 25
    public var shortBreakSeconds: Double = 30
    public var longBreakMinutes: Double = 5
    public var cycles = 2
    public var prealertEnabled = true
    public var warningSeconds: Double = 15
    public var soundEnabled = true
    public var soundName = "Glass"
    public var soundPath: String?
    public var volume: Double = 0.5
    public var messages = ReminderMessage.defaults
    public var shortMessageID = "eyes"
    public var longMessageID = "stretch"
    public var mediaPath: String?
    public var visualID = BuiltinVisual.rings.rawValue

    public init() {}

    public var plan: SessionPlan {
        SessionPlan(workDuration: workMinutes * 60, shortBreakDuration: shortBreakSeconds,
                    longBreakDuration: longBreakMinutes * 60, cycles: cycles,
                    warningSeconds: prealertEnabled ? warningSeconds : 0)
    }

    public func message(for phase: SessionPhase, resolvedID: String? = nil) -> String {
        let id = phase == .longBreak ? longMessageID : shortMessageID
        return messages.first(where: { $0.id == (id == ReminderMessage.randomID ? resolvedID : id) })?.displayText(in: language) ?? ""
    }

    public func containsMessage(_ text: String) -> Bool {
        let key = ReminderMessage.selectionKey(text)
        return messages.contains { message in
            [message.text, message.englishText].compactMap { $0 }.contains { ReminderMessage.selectionKey($0) == key }
        }
    }

    /// Old files may contain duplicate labels; retain the selected ID without deleting user data.
    public func messageChoices(selectedID: String? = nil) -> [ReminderMessage] {
        var result: [ReminderMessage] = []
        var indices: [String: Int] = [:]
        for message in messages {
            let key = ReminderMessage.selectionKey(message.displayText(in: language))
            if let index = indices[key] {
                if message.id == selectedID { result[index] = message }
            } else {
                indices[key] = result.count
                result.append(message)
            }
        }
        return result
    }

    public var hasVisual: Bool { mediaPath != nil || visualID != BuiltinVisual.noneID }

    /// A silent break still runs through the normal cycle, without windows or keyboard capture.
    public func showsBreakScreen(for phase: SessionPhase) -> Bool {
        guard phase.isBreak else { return false }
        let messageID = phase == .longBreak ? longMessageID : shortMessageID
        return hasVisual || messageID != ReminderMessage.noneID
    }

    public var hasSound: Bool {
        soundEnabled && volume > 0 && (soundPath != nil || soundName != Self.noSoundID)
    }

    public func shouldPrealert(for phase: SessionPhase) -> Bool {
        phase.isBreak && prealertEnabled && (showsBreakScreen(for: phase) || hasSound)
    }

    public func validate() throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid(message) }
        }
        try check(schemaVersion == 1, "schemaVersion must be 1")
        for (name, value, range) in [
            ("workMinutes", workMinutes, 1.0...240.0),
            ("shortBreakSeconds", shortBreakSeconds, 5.0...1800.0),
            ("longBreakMinutes", longBreakMinutes, 1.0...120.0),
            ("warningSeconds", warningSeconds, 3.0...120.0),
            ("volume", volume, 0.0...1.0),
            ("breakTransparency", breakTransparency, 0.0...1.0),
        ] {
            try check(value.isFinite && range.contains(value), "\(name) must be within \(range)")
        }
        let shortcuts = [pauseShortcut, restartShortcut, restNowShortcut].compactMap { $0 }
        for shortcut in shortcuts {
            do { try shortcut.validate() }
            catch { throw ConfigurationError.invalid(language.text("请使用 ⌘、⌃ 或 ⌥ 搭配按键；Esc 用于关闭休息界面。", "Use Command, Control or Option with a key; Esc closes the break screen.")) }
        }
        try check(Set(shortcuts).count == shortcuts.count, language.text("快捷键重复，请为每个操作设置不同的快捷键。", "Shortcuts must be different for each action"))
        try check((1...20).contains(cycles), "cycles must be within 1...20")
        try check((1...100).contains(messages.count), "messages must contain 1...100 entries")
        try check(Set(messages.map(\.id)).count == messages.count, "message IDs must be unique")
        for message in messages {
            try check(!message.id.isEmpty && ![ReminderMessage.randomID, ReminderMessage.noneID].contains(message.id) && message.id.count <= 100, "message ID must contain 1...100 characters and cannot be reserved")
            try check(!message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.text.count <= 2000,
                      "message text must contain 1...2000 characters")
            if let englishText = message.englishText {
                try check(!englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && englishText.count <= 2000,
                          "englishText must contain 1...2000 characters")
            }
        }
        try check([ReminderMessage.randomID, ReminderMessage.noneID].contains(shortMessageID) || messages.contains(where: { $0.id == shortMessageID }), "shortMessageID must refer to a message, __random__ or __none__")
        try check([ReminderMessage.randomID, ReminderMessage.noneID].contains(longMessageID) || messages.contains(where: { $0.id == longMessageID }), "longMessageID must refer to a message, __random__ or __none__")
        try check([BuiltinVisual.randomID, BuiltinVisual.noneID].contains(visualID) || BuiltinVisual(rawValue: visualID) != nil, "visualID must name a built-in visual, __random__ or __none__")
        for path in [mediaPath, soundPath].compactMap({ $0 }) {
            try check(!path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !path.contains("\0"),
                      "file paths must be nonempty local paths")
            try check(!path.contains("://"), "remote URLs are not supported")
        }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, language, showMenuBarTime, checkForUpdatesAutomatically, breakTransparency, launchAtLogin, pauseShortcut, restartShortcut, restNowShortcut, workMinutes, shortBreakSeconds, longBreakMinutes
        case cycles, prealertEnabled, warningSeconds, soundEnabled, soundName, soundPath, volume
        case messages, shortMessageID, longMessageID, mediaPath, visualID
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue) + ["visualGrayness", "visualOpacity"])
        let unknown = raw.allKeys.map(\.stringValue).filter { !known.contains($0) }
        guard unknown.isEmpty else { throw ConfigurationError.invalid("Unknown setting: \(unknown.sorted().joined(separator: ", "))") }
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try values.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        schemaVersion = try value(.schemaVersion, schemaVersion)
        language = try value(.language, language)
        showMenuBarTime = try value(.showMenuBarTime, showMenuBarTime)
        checkForUpdatesAutomatically = try value(.checkForUpdatesAutomatically, checkForUpdatesAutomatically)
        breakTransparency = try value(.breakTransparency, breakTransparency)
        // Legacy controls affected only the artwork; a new desktop-covering setting starts opaque.
        for name in ["visualGrayness", "visualOpacity"] {
            if let key = AnyKey(stringValue: name), raw.contains(key) {
                let legacy = try raw.decode(Double.self, forKey: key)
                guard legacy.isFinite && (0...1).contains(legacy) else {
                    throw ConfigurationError.invalid("\(name) must be within 0...1")
                }
            }
        }
        launchAtLogin = try value(.launchAtLogin, launchAtLogin)
        pauseShortcut = try values.decodeIfPresent(KeyboardShortcut.self, forKey: .pauseShortcut)
        restartShortcut = try values.decodeIfPresent(KeyboardShortcut.self, forKey: .restartShortcut)
        restNowShortcut = try values.decodeIfPresent(KeyboardShortcut.self, forKey: .restNowShortcut)
        workMinutes = try value(.workMinutes, workMinutes)
        shortBreakSeconds = try value(.shortBreakSeconds, shortBreakSeconds)
        longBreakMinutes = try value(.longBreakMinutes, longBreakMinutes)
        cycles = try value(.cycles, cycles)
        prealertEnabled = try value(.prealertEnabled, prealertEnabled)
        warningSeconds = try value(.warningSeconds, warningSeconds)
        soundEnabled = try value(.soundEnabled, soundEnabled)
        soundName = try value(.soundName, soundName)
        volume = try value(.volume, volume)
        messages = try value(.messages, messages)
        messages = messages.map { message in
            var migrated = message
            if message.id == "stillness" {
                if message.text == "致虚极，守静笃。——《道德经》第十六章" { migrated.text = "致虚极，守静笃。" }
                if message.englishText == "Empty the mind; remain deeply still. — Dao De Jing, 16" { migrated.englishText = "Empty the mind; remain deeply still." }
            }
            if message.id == "water" {
                if message.text == "上善若水。——《道德经》第八章" { migrated.text = "上善若水。" }
                if message.englishText == "The highest goodness is like water. — Dao De Jing, 8" { migrated.englishText = "The highest goodness is like water." }
            }
            if message.id == "journey" {
                if message.text == "千里之行，始于足下。——《道德经》第六十四章" { migrated.text = "千里之行，始于足下。" }
                if message.englishText == "A journey of a thousand miles begins beneath your feet. — Dao De Jing, 64" { migrated.englishText = "A journey of a thousand miles begins beneath your feet." }
            }
            if message.id == "balance" {
                if message.text == "文武之道，一张一弛。——《礼记·杂记下》" { migrated.text = "文武之道，一张一弛。" }
                if message.englishText == "The way of balance is to alternate tension and relaxation. — Book of Rites" { migrated.englishText = "The way of balance is to alternate tension and relaxation." }
            }
            if message.id == "joy" {
                if message.text == "知之者不如好之者，好之者不如乐之者。——《论语·雍也》" { migrated.text = "知之者不如好之者，好之者不如乐之者。" }
                if message.englishText == "Knowing is less than loving; loving is less than finding joy. — Analects, Yong Ye" { migrated.englishText = "Knowing is less than loving; loving is less than finding joy." }
            }
            if message.id == "nature" {
                if message.text == "人法地，地法天，天法道，道法自然。——《道德经》第二十五章" { migrated.text = "人法地，地法天，天法道，道法自然。" }
                if message.englishText == "Human follows earth, earth follows heaven, heaven follows the Way, and the Way follows nature. — Dao De Jing, 25" { migrated.englishText = "Human follows earth, earth follows heaven, heaven follows the Way, and the Way follows nature." }
            }
            if message.id == "learn" {
                if message.text == "三人行，必有我师焉。——《论语·述而》" { migrated.text = "三人行，必有我师焉。" }
                if message.englishText == "Among any three people walking together, there is someone I can learn from. — Analects, Shu Er" { migrated.englishText = "Among any three people walking together, there is someone I can learn from." }
            }
            if message.id == "flow" {
                if message.text == "逝者如斯夫，不舍昼夜。——《论语·子罕》" { migrated.text = "逝者如斯夫，不舍昼夜。" }
                if message.englishText == "It flows on like this, never ceasing day or night. — Analects, Zi Han" { migrated.englishText = "It flows on like this, never ceasing day or night." }
            }
            return migrated
        }
        shortMessageID = try value(.shortMessageID, shortMessageID)
        longMessageID = try value(.longMessageID, longMessageID)
        visualID = try value(.visualID, visualID)
        soundPath = try values.decodeIfPresent(String.self, forKey: .soundPath)
        mediaPath = try values.decodeIfPresent(String.self, forKey: .mediaPath)
        try validate()
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

public enum ConfigurationError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

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

    public static let randomID = "__random__"

    public static let defaults: [ReminderMessage] = [
        .init(id: "eyes", text: "看向远方，让眼睛休息一下。", englishText: "Look into the distance. Give your eyes a rest."),
        .init(id: "stretch", text: "站起来，伸个懒腰，喝一杯水。", englishText: "Stand up, stretch, and have some water."),
        .init(id: "breathe", text: "放松肩膀，慢慢呼吸。", englishText: "Relax your shoulders. Take a slow breath."),
        .init(id: "walk", text: "离开屏幕，走动一会儿 🌿", englishText: "Step away from the screen. Take a little walk 🌿"),
        .init(id: "stillness", text: "致虚极，守静笃。——《道德经》第十六章", englishText: "Empty the mind; remain deeply still. — Dao De Jing, 16"),
        .init(id: "water", text: "上善若水。——《道德经》第八章", englishText: "The highest goodness is like water. — Dao De Jing, 8"),
        .init(id: "journey", text: "千里之行，始于足下。——《道德经》第六十四章", englishText: "A journey of a thousand miles begins beneath your feet. — Dao De Jing, 64"),
        .init(id: "balance", text: "文武之道，一张一弛。——《礼记·杂记下》", englishText: "The way of balance is to alternate tension and relaxation. — Book of Rites"),
        .init(id: "joy", text: "知之者不如好之者，好之者不如乐之者。——《论语·雍也》", englishText: "Knowing is less than loving; loving is less than finding joy. — Analects, Yong Ye"),
        .init(id: "nature", text: "人法地，地法天，天法道，道法自然。——《道德经》第二十五章", englishText: "Human follows earth, earth follows heaven, heaven follows the Way, and the Way follows nature. — Dao De Jing, 25"),
        .init(id: "learn", text: "三人行，必有我师焉。——《论语·述而》", englishText: "Among any three people walking together, there is someone I can learn from. — Analects, Shu Er"),
        .init(id: "flow", text: "逝者如斯夫，不舍昼夜。——《论语·子罕》", englishText: "It flows on like this, never ceasing day or night. — Analects, Zi Han"),
    ]
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var language: AppLanguage = .simplifiedChinese
    public var showMenuBarTime = true
    public var checkForUpdatesAutomatically = true
    public var visualGrayness: Double = 0
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
            ("visualGrayness", visualGrayness, 0.0...1.0),
        ] {
            try check(value.isFinite && range.contains(value), "\(name) must be within \(range)")
        }
        try check((1...20).contains(cycles), "cycles must be within 1...20")
        try check((1...100).contains(messages.count), "messages must contain 1...100 entries")
        try check(Set(messages.map(\.id)).count == messages.count, "message IDs must be unique")
        for message in messages {
            try check(!message.id.isEmpty && message.id != ReminderMessage.randomID && message.id.count <= 100, "message ID must contain 1...100 characters")
            try check(!message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.text.count <= 2000,
                      "message text must contain 1...2000 characters")
            if let englishText = message.englishText {
                try check(!englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && englishText.count <= 2000,
                          "englishText must contain 1...2000 characters")
            }
        }
        try check(shortMessageID == ReminderMessage.randomID || messages.contains(where: { $0.id == shortMessageID }), "shortMessageID must refer to a message")
        try check(longMessageID == ReminderMessage.randomID || messages.contains(where: { $0.id == longMessageID }), "longMessageID must refer to a message")
        try check(visualID == BuiltinVisual.randomID || BuiltinVisual(rawValue: visualID) != nil, "visualID must name a built-in visual or __random__")
        for path in [mediaPath, soundPath].compactMap({ $0 }) {
            try check(!path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !path.contains("\0"),
                      "file paths must be nonempty local paths")
            try check(!path.contains("://"), "remote URLs are not supported")
        }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, language, showMenuBarTime, checkForUpdatesAutomatically, visualGrayness, workMinutes, shortBreakSeconds, longBreakMinutes
        case cycles, prealertEnabled, warningSeconds, soundEnabled, soundName, soundPath, volume
        case messages, shortMessageID, longMessageID, mediaPath, visualID
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !known.contains($0) }
        guard unknown.isEmpty else { throw ConfigurationError.invalid("Unknown setting: \(unknown.sorted().joined(separator: ", "))") }
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try values.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        schemaVersion = try value(.schemaVersion, schemaVersion)
        language = try value(.language, language)
        showMenuBarTime = try value(.showMenuBarTime, showMenuBarTime)
        checkForUpdatesAutomatically = try value(.checkForUpdatesAutomatically, checkForUpdatesAutomatically)
        visualGrayness = try value(.visualGrayness, visualGrayness)
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

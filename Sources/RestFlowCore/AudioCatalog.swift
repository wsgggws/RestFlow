import Foundation

public enum AlertTone: String, CaseIterable, Sendable {
    case glass = "Glass", tink = "Tink", ping = "Ping", purr = "Purr", pop = "Pop", blow = "Blow"
    case bottle = "Bottle", frog = "Frog", funk = "Funk", hero = "Hero", sosumi = "Sosumi", submarine = "Submarine"
    public func title(in language: AppLanguage) -> String { rawValue }
}

public enum FocusNoise: String, CaseIterable, Sendable {
    case white, pink, brown, lightRain, heavyRain, ocean, wind, stream, fan, leaves, fire, night
    public func title(in language: AppLanguage) -> String {
        switch self {
        case .white: return language.text("白噪音", "White noise")
        case .pink: return language.text("粉噪音", "Pink noise")
        case .brown: return language.text("棕噪音", "Brown noise")
        case .lightRain: return language.text("细雨", "Light rain")
        case .heavyRain: return language.text("大雨", "Heavy rain")
        case .ocean: return language.text("海浪", "Ocean")
        case .wind: return language.text("风声", "Wind")
        case .stream: return language.text("溪流", "Stream")
        case .fan: return language.text("风扇", "Fan")
        case .leaves: return language.text("树叶", "Leaves")
        case .fire: return language.text("炉火", "Fire")
        case .night: return language.text("夜虫", "Night insects")
        }
    }
}

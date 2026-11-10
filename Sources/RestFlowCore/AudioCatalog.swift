import Foundation

public enum AlertTone: String, CaseIterable, Sendable {
    case glass = "Glass", tink = "Tink", ping = "Ping", purr = "Purr", pop = "Pop", blow = "Blow"
    case bottle = "Bottle", frog = "Frog", funk = "Funk", hero = "Hero", sosumi = "Sosumi", submarine = "Submarine"
    public func title(in language: AppLanguage) -> String { rawValue }
}

public enum FocusNoise: String, CaseIterable, Sendable {
    case train, aircraft, lightRain, ocean, wind, stream, fire, night, thunder, birds, cafe, keyboard
    public func title(in language: AppLanguage) -> String {
        switch self {
        case .train: return language.text("街头车流", "Street traffic")
        case .aircraft: return language.text("池塘蛙鸣", "Pond frogs")
        case .lightRain: return language.text("庭院落雨", "Rain on the ground")
        case .ocean: return language.text("沙滩海浪", "Ocean surf")
        case .wind: return language.text("狂风呼啸", "Howling wind")
        case .stream: return language.text("山间溪流", "Mountain stream")
        case .fire: return language.text("篝火噼啪", "Crackling bonfire")
        case .night: return language.text("夏夜虫鸣", "Summer crickets")
        case .thunder: return language.text("电闪雷鸣", "Cracking thunder")
        case .birds: return language.text("林间鸟鸣", "Forest birds")
        case .cafe: return language.text("人声鼎沸", "Crowd chatter")
        case .keyboard: return language.text("书房键盘", "Study keyboard")
        }
    }

    public static func migrate(_ ids: [String]) -> [String] {
        let replacements = ["white": "lightRain", "pink": "train", "brown": "aircraft",
                            "heavyRain": "lightRain", "fan": "aircraft", "leaves": "wind"]
        var seen = Set<String>()
        return ids.map { replacements[$0] ?? $0 }.filter { seen.insert($0).inserted }
    }
}

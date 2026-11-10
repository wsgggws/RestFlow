import Foundation

public enum AlertTone: String, CaseIterable, Sendable {
    case glass = "Glass"
    case dew, wood, bowl, pebble, windbell, sprout, ripple, starlight, bamboo, dawn, hush

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .glass: return "Glass"
        case .dew: return language.text("晨露", "Dew")
        case .wood: return language.text("木叩", "Wood tap")
        case .bowl: return language.text("清钵", "Singing bowl")
        case .pebble: return language.text("石语", "Pebble")
        case .windbell: return language.text("风铃", "Wind chime")
        case .sprout: return language.text("萌芽", "Sprout")
        case .ripple: return language.text("涟漪", "Ripple")
        case .starlight: return language.text("星芒", "Starlight")
        case .bamboo: return language.text("竹音", "Bamboo")
        case .dawn: return language.text("初晴", "Dawn")
        case .hush: return language.text("轻息", "Soft breath")
        }
    }
}

/// The scene ID also identifies its original synthesized sixteen-second soundtrack.
public enum BackgroundTrack: String, CaseIterable, Sendable {
    case rings, orbit, waves, rain, sunrise, mountains, forest, lotus, stars, clouds, bamboo, fireflies
    public static let matchedID = "__matched__"

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .rings: return language.text("呼吸和弦", "Breathing chords")
        case .orbit: return language.text("星轨回响", "Orbital echoes")
        case .waves: return language.text("潮汐轻吟", "Tidal hum")
        case .rain: return language.text("雨落琴弦", "Rain strings")
        case .sunrise: return language.text("晨光渐起", "Morning light")
        case .mountains: return language.text("山间长风", "Mountain air")
        case .forest: return language.text("林间鸟语", "Forest birds")
        case .lotus: return language.text("莲池泛音", "Lotus harmonics")
        case .stars: return language.text("星夜微钟", "Night bells")
        case .clouds: return language.text("浮云慢调", "Cloud drift")
        case .bamboo: return language.text("竹叶清响", "Bamboo rustle")
        case .fireflies: return language.text("萤光点点", "Firefly notes")
        }
    }
}

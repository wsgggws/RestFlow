import Foundation

public enum BuiltinVisual: String, CaseIterable, Codable, Sendable {
    case rings, orbit, waves, rain, sunrise, mountains, forest, lotus, stars, clouds, bamboo, fireflies
    public static let randomID = "__random__"

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .rings: return language.text("呼吸圆环", "Breathing rings")
        case .orbit: return language.text("环绕星点", "Orbiting dots")
        case .waves: return language.text("轻柔海浪", "Gentle waves")
        case .rain: return language.text("听雨时分", "Quiet rain")
        case .sunrise: return language.text("日出微光", "Sunrise")
        case .mountains: return language.text("远山如黛", "Distant mountains")
        case .forest: return language.text("林间片刻", "Forest pause")
        case .lotus: return language.text("莲瓣舒展", "Unfolding lotus")
        case .stars: return language.text("静谧星空", "Quiet stars")
        case .bamboo: return language.text("竹影清风", "Bamboo breeze")
        case .fireflies: return language.text("萤火微光", "Firefly glow")
        case .clouds: return language.text("云卷云舒", "Drifting clouds")
        }
    }
}

/// One selection per break/preview, shared across displays and timer refreshes.
/// Store IDs so language changes translate the same selected message immediately.
public struct BreakContent: Equatable, Sendable {
    public let shortMessageID: String
    public let longMessageID: String
    public let visual: BuiltinVisual

    public init(settings: AppSettings, choose: ([String]) -> String = { $0.randomElement()! }) {
        func resolve(_ id: String) -> String {
            id == ReminderMessage.randomID ? choose(settings.messages.map(\.id)) : id
        }
        shortMessageID = resolve(settings.shortMessageID)
        longMessageID = resolve(settings.longMessageID)
        let visualID = settings.visualID == BuiltinVisual.randomID
            ? choose(BuiltinVisual.allCases.map(\.rawValue)) : settings.visualID
        visual = BuiltinVisual(rawValue: visualID) ?? .rings
    }

    public func message(for phase: SessionPhase, settings: AppSettings) -> String {
        settings.message(for: phase, resolvedID: phase == .longBreak ? longMessageID : shortMessageID)
    }
}

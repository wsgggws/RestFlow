import Foundation
import RestFlowCore

enum SettingsMigration {
    /// Read old preferences once; config.json takes precedence on every subsequent launch.
    static func legacySettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "RestFlow.settings.v1"),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return AppSettings() }
        let shortText = json.removeValue(forKey: "shortBreakText") as? String
        let longText = json.removeValue(forKey: "longBreakText") as? String
        let folder = json.removeValue(forKey: "mediaFolder") as? String
        let file = json.removeValue(forKey: "mediaFileName") as? String
        json.removeValue(forKey: "mediaDisplayName")
        guard let cleaned = try? JSONSerialization.data(withJSONObject: json),
              var settings = try? ConfigurationStore.decode(cleaned) else { return AppSettings() }
        for (text, isLong) in [(shortText, false), (longText, true)] {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let id: String
            if let match = settings.messages.first(where: { $0.text == text }) { id = match.id }
            else {
                let message = ReminderMessage(text: text)
                settings.messages.append(message)
                id = message.id
            }
            if isLong { settings.longMessageID = id } else { settings.shortMessageID = id }
        }
        if let folder, let file, UUID(uuidString: folder) != nil,
           file == URL(fileURLWithPath: file).lastPathComponent {
            settings.mediaPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RestFlow/Media/\(folder)/\(file)").path
        }
        return (try? settings.validate()) != nil ? settings : AppSettings()
    }
}

import Foundation

enum AppIdentity {
    /// Bundle localization follows macOS language preferences, independently of the in-app UI language.
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "RestFlow"
    }

    static func checkIntegration() -> Int32 {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(language).lproj/InfoPlist.strings")
            let data = try? Data(contentsOf: url)
            let values = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: String] }
            let expected = language == "en" ? "RestFlow" : "坐忘录"
            check(values?["CFBundleName"] == expected && values?["CFBundleDisplayName"] == expected,
                  "\(language) bundle contains localized app names")
        }
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let expected = language.hasPrefix("zh") ? "坐忘录" : "RestFlow"
        check(displayName == expected, "system language \(language) displays \(expected)")
        check(Bundle.main.infoDictionary?["CFBundleName"] as? String == "RestFlow" &&
              Bundle.main.bundleURL.lastPathComponent == "RestFlow.app", "English bundle identity and filename remain stable")
        let names = Bundle.main.object(forInfoDictionaryKey: "CFBundleAlternateNames") as? [String] ?? []
        check(names.contains("RestFlow") && names.contains("坐忘录"), "Spotlight aliases contain both Chinese and English names")
        return failures == 0 ? 0 : 1
    }
}

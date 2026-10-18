import Foundation

nonisolated enum AppLanguage {
    static let preferenceKey = "Clean.language"
    static let choices = [("system", "Automatic"), ("zh-Hans", "简体中文"), ("en", "English"), ("ja", "日本語"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español")]
    static var systemLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    }
    static var current: String { resolve(UserDefaults.standard.string(forKey: preferenceKey) ?? "system") }
    static var locale: Locale { Locale(identifier: current) }
    static func resolve(_ choice: String, preferred: [String] = AppLanguage.systemLanguages) -> String {
        if choice != "system", choices.contains(where: { $0.0 == choice }) { return choice }
        for language in preferred {
            let code = language.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
            if code == "zh" { return "zh-Hans" }
            if ["en", "ja", "de", "fr", "es"].contains(code) { return code }
        }
        return "en"
    }
}

nonisolated enum Localization {
    static let translations: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return value
    }()
    static func text(_ key: String, language: String = AppLanguage.current, arguments: [String] = []) -> String {
        let template = language == "zh-Hans" ? key : translations[key]?[language] ?? translations[key]?["en"] ?? key
        // Split the template before inserting arguments, so filenames containing {1} remain literal.
        var result = ""
        var rest = template[...]
        while let start = rest.firstIndex(of: "{"), let end = rest[start...].firstIndex(of: "}") {
            result += rest[..<start]
            let token = rest[rest.index(after: start)..<end]
            if let index = Int(token), arguments.indices.contains(index) { result += arguments[index] }
            else { result += rest[start...end] }
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }
}

nonisolated func L(_ key: String, _ arguments: String...) -> String {
    Localization.text(key, arguments: arguments)
}

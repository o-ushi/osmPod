import Foundation

private let kLanguageKey = "appLanguage"

@MainActor
@Observable
final class LanguageSettings {
    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: kLanguageKey) }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: kLanguageKey),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = AppLanguage.defaultInstallLanguage
            UserDefaults.standard.set(language.rawValue, forKey: kLanguageKey)
        }
    }

    var strings: LocalizedStrings { LocalizedStrings(language: language) }
}

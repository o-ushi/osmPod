import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case japanese = "ja"
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    var flag: String {
        switch self {
        case .japanese: return "🇯🇵"
        case .english: return "🇺🇸"
        case .vietnamese: return "🇻🇳"
        }
    }

    var locale: Locale {
        switch self {
        case .japanese: Locale(identifier: "ja_JP")
        case .english: Locale(identifier: "en_US")
        case .vietnamese: Locale(identifier: "vi_VN")
        }
    }

    /// UserDefaults に言語が未保存のときの既定（初回インストール時と同じ）。
    static let defaultInstallLanguage: AppLanguage = .english

    static func detectSystemLanguage() -> AppLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("vi") { return .vietnamese }
        return .english
    }
}

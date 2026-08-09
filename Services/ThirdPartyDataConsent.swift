import Foundation

/// 番組検索（iTunes Search API への送信）に対する同意状態。
/// `UserDefaults` に符号付きバージョン番号で保存する: `+currentVersion` = 同意, `-currentVersion` = 拒否, `0`/未設定 = 未決定。
/// `currentVersion` を上げると、既存ユーザーにも再同意を求められる。
enum ThirdPartyDataConsent {
    static let currentVersion = 1
    static let storageKey = "privacy.searchConsent.version"

    static var storedDecision: Int {
        UserDefaults.standard.integer(forKey: storageKey)
    }

    static var hasCurrentDecision: Bool { abs(storedDecision) == currentVersion }
    static var isGranted: Bool { storedDecision == currentVersion }

    static func grant() {
        UserDefaults.standard.set(currentVersion, forKey: storageKey)
    }

    static func decline() {
        UserDefaults.standard.set(-currentVersion, forKey: storageKey)
    }

    static func deleteDecision() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// 同意未取得のまま番組検索が呼ばれたときに投げるエラー。呼び出し元は `error.localizedDescription` をそのまま表示できる。
struct PodcastSearchConsentError: LocalizedError {
    var errorDescription: String? {
        PrivacyText.consentRequiredMessage(LocalizedStrings.current.language)
    }
}

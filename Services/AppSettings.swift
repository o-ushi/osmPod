import Foundation
import UIKit

enum AutoPlayOrder: String, CaseIterable, Identifiable {
    case newest = "newest"
    case oldest = "oldest"
    case random = "random"

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .newest:
            switch language {
            case .japanese: return "新しいエピソードから"
            case .english: return "Newest first"
            case .vietnamese: return "Mới nhất trước"
            }
        case .oldest:
            switch language {
            case .japanese: return "古いエピソードから"
            case .english: return "Oldest first"
            case .vietnamese: return "Cũ nhất trước"
            }
        case .random:
            switch language {
            case .japanese: return "ランダム"
            case .english: return "Random"
            case .vietnamese: return "Ngẫu nhiên"
            }
        }
    }
}

enum HapticIntensity: String, CaseIterable, Identifiable {
    case light = "light"
    case medium = "medium"
    case strong = "strong"

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .light:
            switch language {
            case .japanese: return "弱"
            case .english: return "Light"
            case .vietnamese: return "Nhẹ"
            }
        case .medium:
            switch language {
            case .japanese: return "中"
            case .english: return "Medium"
            case .vietnamese: return "Trung bình"
            }
        case .strong:
            switch language {
            case .japanese: return "強"
            case .english: return "Strong"
            case .vietnamese: return "Mạnh"
            }
        }
    }

    var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light:  return .light
        case .medium: return .medium
        case .strong: return .heavy
        }
    }
}

enum DateFormat: String, CaseIterable, Identifiable {
    case yyyyMMdd = "yyyy/MM/dd"
    case ddMMyyyy = "dd/MM/yyyy"

    var id: String { rawValue }
}

enum FolderOrderOption: String, CaseIterable {
    case name
    case date
}

enum EpisodeOrderOption: String, CaseIterable {
    case name
    case date
}

enum AppSettings {
    private static let dateFormatKey = "dateFormat"
    private static let shakeRewindKey = "shakeRewindSeconds"
    private static let folderOrderKey = "folderOrderOption"
    private static let episodeOrderKey = "episodeOrderOption"
    private static let folderSortAscendingKey = "folderSortAscending"
    private static let episodeSortAscendingKey = "episodeSortAscending"
    private static let enableHapticKey = "enableHapticFeedback"
    private static let hapticIntensityKey = "hapticIntensity"
    private static let enableSoundKey = "enableSoundFeedback"
    private static let soundVolumeKey = "soundVolume"
    private static let folderExpansionStatesKey = "folderExpansionStates"
    private static let folderExpandedShowsKey = "folderExpandedShows"
    private static let skipPlayedEpisodesKey = "skipPlayedEpisodes"
    private static let hidePlayedEpisodesKey = "hidePlayedEpisodes"
    private static let autoPlayEnabledKey = "autoPlayEnabled"
    private static let autoPlayOrderKey = "autoPlayOrder"
    private static let autoPlayExcludedShowFeedURLsKey = "autoPlayExcludedShowFeedURLs"
    private static let randomModeEnabledKey = "randomModeEnabled"
    private static let lastPlayingEpisodeAudioURLKey = "lastPlayingEpisodeAudioURL"
    private static let cloudSyncEnabledKey = "cloudSyncEnabled"
    private static let lastCloudSyncDateKey = "lastCloudSyncDate"
    private static let developerModeEnabledKey = "developerModeEnabled"
    private static let developerModeEnabledAtKey = "developerModeEnabledAt"

    static var dateFormat: DateFormat {
        get {
            let raw = UserDefaults.standard.string(forKey: dateFormatKey)
            return DateFormat(rawValue: raw ?? "") ?? .yyyyMMdd
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dateFormatKey) }
    }

    /// シェイクで巻き戻す秒数（既定 15）
    static var shakeRewindSeconds: TimeInterval {
        get {
            let v = UserDefaults.standard.object(forKey: shakeRewindKey) as? Double
            if let v, v > 0 { return v }
            return 15
        }
        set {
            UserDefaults.standard.set(newValue, forKey: shakeRewindKey)
        }
    }

    /// サブフォルダの並び（トップレベルのフォルダは常に `sortOrder` で並べ替え）。
    static var subfolderOrderOption: FolderOrderOption {
        get {
            let raw = UserDefaults.standard.string(forKey: folderOrderKey)
            if raw == "manual" { return .name }
            return FolderOrderOption(rawValue: raw ?? "") ?? .name
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: folderOrderKey)
        }
    }

    /// 後方互換の別名。
    static var folderOrderOption: FolderOrderOption {
        get { subfolderOrderOption }
        set { subfolderOrderOption = newValue }
    }

    static var episodeOrderOption: EpisodeOrderOption {
        get {
            let raw = UserDefaults.standard.string(forKey: episodeOrderKey)
            return EpisodeOrderOption(rawValue: raw ?? "") ?? .date
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: episodeOrderKey)
        }
    }

    static var folderSortAscending: Bool {
        get {
            guard UserDefaults.standard.object(forKey: folderSortAscendingKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: folderSortAscendingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: folderSortAscendingKey)
        }
    }

    static var episodeSortAscending: Bool {
        get {
            guard UserDefaults.standard.object(forKey: episodeSortAscendingKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: episodeSortAscendingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: episodeSortAscendingKey)
        }
    }

    static var enableHapticFeedback: Bool {
        get { UserDefaults.standard.object(forKey: enableHapticKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enableHapticKey) }
    }

    static var hapticIntensity: HapticIntensity {
        get {
            let raw = UserDefaults.standard.string(forKey: hapticIntensityKey)
            return HapticIntensity(rawValue: raw ?? "") ?? .medium
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: hapticIntensityKey) }
    }

    static var enableSoundFeedback: Bool {
        get { UserDefaults.standard.object(forKey: enableSoundKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enableSoundKey) }
    }

    static var soundVolume: Double {
        get { UserDefaults.standard.object(forKey: soundVolumeKey) as? Double ?? 0.5 }
        set { UserDefaults.standard.set(newValue, forKey: soundVolumeKey) }
    }

    static var skipPlayedEpisodes: Bool {
        get { UserDefaults.standard.object(forKey: skipPlayedEpisodesKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: skipPlayedEpisodesKey) }
    }

    /// ライブラリのエピソード一覧から再生済みを隠す（既定: 表示する）。
    static var hidePlayedEpisodes: Bool {
        get { UserDefaults.standard.object(forKey: hidePlayedEpisodesKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: hidePlayedEpisodesKey) }
    }

    static var autoPlayEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoPlayEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: autoPlayEnabledKey) }
    }

    static var autoPlayOrder: AutoPlayOrder {
        get {
            let raw = UserDefaults.standard.string(forKey: autoPlayOrderKey)
            return AutoPlayOrder(rawValue: raw ?? "") ?? .newest
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: autoPlayOrderKey) }
    }

    static var randomModeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: randomModeEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: randomModeEnabledKey) }
    }

    /// 設定画面の最下部を7回タップすると切り替わる開発者向けデバッグメニューの表示状態。
    static var developerModeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: developerModeEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: developerModeEnabledKey) }
    }

    /// 開発者モードを最後に ON にした日時（ログ共有ヘッダの目安表示用）。
    static var developerModeEnabledAt: Date? {
        get { UserDefaults.standard.object(forKey: developerModeEnabledAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: developerModeEnabledAtKey) }
    }

    /// 最後に再生していたエピソードの audioURL（アプリ終了後の復元用）。
    static var lastPlayingEpisodeAudioURL: String? {
        get { UserDefaults.standard.string(forKey: lastPlayingEpisodeAudioURLKey) }
        set {
            if let url = newValue {
                UserDefaults.standard.set(url, forKey: lastPlayingEpisodeAudioURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastPlayingEpisodeAudioURLKey)
            }
        }
    }

    static var autoPlayExcludedShowFeedURLs: Set<String> {
        get {
            let arr = UserDefaults.standard.array(forKey: autoPlayExcludedShowFeedURLsKey) as? [String] ?? []
            return Set(arr)
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: autoPlayExcludedShowFeedURLsKey) }
    }

    static func isFolderExpanded(folderID: String, defaultValue: Bool) -> Bool {
        let states = UserDefaults.standard.dictionary(forKey: folderExpansionStatesKey) as? [String: Bool] ?? [:]
        return states[folderID] ?? defaultValue
    }

    static func setFolderExpanded(_ isExpanded: Bool, folderID: String) {
        var states = UserDefaults.standard.dictionary(forKey: folderExpansionStatesKey) as? [String: Bool] ?? [:]
        states[folderID] = isExpanded
        UserDefaults.standard.set(states, forKey: folderExpansionStatesKey)
    }

    static func expandedShowIDs(folderID: String) -> Set<String> {
        let states = UserDefaults.standard.dictionary(forKey: folderExpandedShowsKey) as? [String: [String]] ?? [:]
        return Set(states[folderID] ?? [])
    }

    static func setExpandedShowIDs(_ showIDs: Set<String>, folderID: String) {
        var states = UserDefaults.standard.dictionary(forKey: folderExpandedShowsKey) as? [String: [String]] ?? [:]
        states[folderID] = Array(showIDs)
        UserDefaults.standard.set(states, forKey: folderExpandedShowsKey)
    }

    // MARK: - Cloud Sync

    static var cloudSyncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: cloudSyncEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: cloudSyncEnabledKey) }
    }

    static var lastCloudSyncDate: Date? {
        get {
            guard let interval = UserDefaults.standard.object(forKey: lastCloudSyncDateKey) as? Double else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastCloudSyncDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastCloudSyncDateKey)
            }
        }
    }

}

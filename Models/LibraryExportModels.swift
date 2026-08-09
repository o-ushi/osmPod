import Foundation

/// アプリのフォルダ／番組構成を JSON でやり取りするための型。
struct OsmPodLibraryExport: Codable {
    static let currentVersion = 2

    var version: Int
    var exportedAt: Date
    /// ルート直下のフォルダツリー
    var rootFolders: [ExportedFolderBranch]
    /// どのフォルダにも属さない番組のフィード URL
    var orphanShowFeedURLs: [String]
    /// ルート以外の階層に置かれた番組（フォルダ単体を選ばず番組だけエクスポートした場合など）
    var showAssignments: [ExportedShowAssignment]
    /// エピソードごとの再生状態（再生済み・再生中・新着・お気に入り）
    var episodeStates: [ExportedEpisodeState]
    /// アプリ設定一式
    var settings: ExportedSettings?

    enum CodingKeys: String, CodingKey {
        case version, exportedAt, rootFolders, orphanShowFeedURLs, showAssignments, episodeStates, settings
    }

    init(
        version: Int = Self.currentVersion,
        exportedAt: Date = .now,
        rootFolders: [ExportedFolderBranch],
        orphanShowFeedURLs: [String] = [],
        showAssignments: [ExportedShowAssignment] = [],
        episodeStates: [ExportedEpisodeState] = [],
        settings: ExportedSettings? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.rootFolders = rootFolders
        self.orphanShowFeedURLs = orphanShowFeedURLs
        self.showAssignments = showAssignments
        self.episodeStates = episodeStates
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        rootFolders = try c.decode([ExportedFolderBranch].self, forKey: .rootFolders)
        orphanShowFeedURLs = try c.decodeIfPresent([String].self, forKey: .orphanShowFeedURLs) ?? []
        showAssignments = try c.decodeIfPresent([ExportedShowAssignment].self, forKey: .showAssignments) ?? []
        episodeStates = try c.decodeIfPresent([ExportedEpisodeState].self, forKey: .episodeStates) ?? []
        settings = try c.decodeIfPresent(ExportedSettings.self, forKey: .settings)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(exportedAt, forKey: .exportedAt)
        try c.encode(rootFolders, forKey: .rootFolders)
        try c.encode(orphanShowFeedURLs, forKey: .orphanShowFeedURLs)
        try c.encode(showAssignments, forKey: .showAssignments)
        try c.encode(episodeStates, forKey: .episodeStates)
        try c.encodeIfPresent(settings, forKey: .settings)
    }
}

/// 番組と、そのときの所属フォルダパス（ルートからのフォルダ名）
struct ExportedShowAssignment: Codable {
    var feedURL: String
    var pathFromRoot: [String]
}

struct ExportedFolderBranch: Codable {
    var name: String
    var iconName: String
    var sortOrder: Int
    var children: [ExportedFolderBranch]
    /// このフォルダに割り当てられた番組のフィード URL
    var assignedShowFeedURLs: [String]
    /// フォルダに直接入っているエピソード（番組横断）
    var folderEpisodeRefs: [ExportedFolderEpisodeRef]
}

struct ExportedFolderEpisodeRef: Codable {
    var showFeedURL: String
    var audioURL: String
}

struct ExportedSettings: Codable {
    var language: String
    var shakeRewindSeconds: Double
    var folderOrderOption: String
    var episodeOrderOption: String
    var folderSortAscending: Bool
    var episodeSortAscending: Bool
    var enableHapticFeedback: Bool
    var hapticIntensity: String
    var enableSoundFeedback: Bool
    var soundVolume: Double
    var skipPlayedEpisodes: Bool
    var hidePlayedEpisodes: Bool?

    enum CodingKeys: String, CodingKey {
        case language, shakeRewindSeconds
        case folderOrderOption, episodeOrderOption
        case folderSortAscending, episodeSortAscending
        case enableHapticFeedback, hapticIntensity
        case enableSoundFeedback, soundVolume
        case skipPlayedEpisodes, hidePlayedEpisodes
    }

    init(
        language: String,
        shakeRewindSeconds: Double,
        folderOrderOption: String,
        episodeOrderOption: String,
        folderSortAscending: Bool,
        episodeSortAscending: Bool,
        enableHapticFeedback: Bool,
        hapticIntensity: String,
        enableSoundFeedback: Bool,
        soundVolume: Double,
        skipPlayedEpisodes: Bool,
        hidePlayedEpisodes: Bool? = nil
    ) {
        self.language = language
        self.shakeRewindSeconds = shakeRewindSeconds
        self.folderOrderOption = folderOrderOption
        self.episodeOrderOption = episodeOrderOption
        self.folderSortAscending = folderSortAscending
        self.episodeSortAscending = episodeSortAscending
        self.enableHapticFeedback = enableHapticFeedback
        self.hapticIntensity = hapticIntensity
        self.enableSoundFeedback = enableSoundFeedback
        self.soundVolume = soundVolume
        self.skipPlayedEpisodes = skipPlayedEpisodes
        self.hidePlayedEpisodes = hidePlayedEpisodes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decode(String.self, forKey: .language)
        shakeRewindSeconds = try c.decode(Double.self, forKey: .shakeRewindSeconds)
        folderOrderOption = try c.decode(String.self, forKey: .folderOrderOption)
        episodeOrderOption = try c.decode(String.self, forKey: .episodeOrderOption)
        folderSortAscending = try c.decode(Bool.self, forKey: .folderSortAscending)
        episodeSortAscending = try c.decode(Bool.self, forKey: .episodeSortAscending)
        enableHapticFeedback = try c.decode(Bool.self, forKey: .enableHapticFeedback)
        hapticIntensity = try c.decode(String.self, forKey: .hapticIntensity)
        enableSoundFeedback = try c.decode(Bool.self, forKey: .enableSoundFeedback)
        soundVolume = try c.decode(Double.self, forKey: .soundVolume)
        skipPlayedEpisodes = try c.decode(Bool.self, forKey: .skipPlayedEpisodes)
        hidePlayedEpisodes = try c.decodeIfPresent(Bool.self, forKey: .hidePlayedEpisodes)
    }
}

struct ExportedEpisodeState: Codable {
    var showFeedURL: String
    var audioURL: String
    var isPlayed: Bool
    var playbackPosition: TimeInterval
    var totalDuration: TimeInterval
    var isNew: Bool
    var isFavorite: Bool
}

import Foundation
import SwiftData
import SwiftUI

/// ライブラリの JSON エクスポート／インポート。
@MainActor
enum LibraryImportExportService {
    struct RefreshResult {
        var refreshedShows: Int
        var updatedEpisodes: Int
        var addedEpisodes: Int
        var failedShows: Int
    }

    // MARK: - Export

    static func buildExportPayload(
        selectedFolderIDs: Set<PersistentIdentifier>,
        selectedShowIDs: Set<PersistentIdentifier>,
        context: ModelContext
    ) throws -> OsmPodLibraryExport {
        let folderDesc = FetchDescriptor<Folder>()
        let allFolders = (try? context.fetch(folderDesc)) ?? []

        func isDescendant(_ folder: Folder, of ancestor: Folder) -> Bool {
            var p: Folder? = folder.parent
            while let cur = p {
                if cur.persistentModelID == ancestor.persistentModelID { return true }
                p = cur.parent
            }
            return false
        }

        let selectedFolders = allFolders.filter { selectedFolderIDs.contains($0.persistentModelID) }
        let topLevelForExport = selectedFolders.filter { candidate in
            !selectedFolders.contains { other in
                other.persistentModelID != candidate.persistentModelID && isDescendant(candidate, of: other)
            }
        }

        let rootBranches = topLevelForExport.map { exportBranch(folder: $0) }

        func showCoveredByFolderExport(_ show: Show) -> Bool {
            for g in show.groups {
                for sf in topLevelForExport {
                    if g.persistentModelID == sf.persistentModelID { return true }
                    if isDescendant(g, of: sf) { return true }
                }
            }
            return false
        }

        var orphanFeeds: [String] = []
        var assignments: [ExportedShowAssignment] = []

        let showDesc = FetchDescriptor<Show>()
        let allShows = (try? context.fetch(showDesc)) ?? []

        for show in allShows where selectedShowIDs.contains(show.persistentModelID) {
            if showCoveredByFolderExport(show) { continue }

            if show.groups.isEmpty {
                if !orphanFeeds.contains(where: { $0 == show.feedURL }) {
                    orphanFeeds.append(show.feedURL)
                }
                continue
            }

            for g in show.groups {
                assignments.append(
                    ExportedShowAssignment(feedURL: show.feedURL, pathFromRoot: folderPathNames(fromRootTo: g))
                )
            }
        }

        var exportedFeedURLs: Set<String> = []
        func collectFeedURLs(from folder: Folder) {
            for show in folder.sortedShows { exportedFeedURLs.insert(show.feedURL) }
            for child in folder.sortedChildren { collectFeedURLs(from: child) }
        }
        for folder in topLevelForExport { collectFeedURLs(from: folder) }
        for show in allShows where selectedShowIDs.contains(show.persistentModelID) {
            exportedFeedURLs.insert(show.feedURL)
        }

        var episodeStates: [ExportedEpisodeState] = []
        for show in allShows where exportedFeedURLs.contains(show.feedURL) {
            for ep in show.episodes {
                guard ep.isPlayed || ep.playbackPosition > 0 || ep.isNew || ep.isFavorite else { continue }
                episodeStates.append(ExportedEpisodeState(
                    showFeedURL: show.feedURL,
                    audioURL: ep.audioURL,
                    isPlayed: ep.isPlayed,
                    playbackPosition: ep.playbackPosition,
                    totalDuration: ep.totalDuration,
                    isNew: ep.isNew,
                    isFavorite: ep.isFavorite
                ))
            }
        }

        return OsmPodLibraryExport(
            exportedAt: .now,
            rootFolders: rootBranches,
            orphanShowFeedURLs: orphanFeeds,
            showAssignments: assignments,
            episodeStates: episodeStates,
            settings: buildSettingsSnapshot()
        )
    }

    private static func buildSettingsSnapshot() -> ExportedSettings {
        let ud = UserDefaults.standard
        return ExportedSettings(
            language: ud.string(forKey: "appLanguage") ?? AppLanguage.defaultInstallLanguage.rawValue,
            shakeRewindSeconds: ud.object(forKey: "shakeRewindSeconds") as? Double ?? 15,
            folderOrderOption: ud.string(forKey: "folderOrderOption") ?? "name",
            episodeOrderOption: ud.string(forKey: "episodeOrderOption") ?? "date",
            folderSortAscending: ud.object(forKey: "folderSortAscending") as? Bool ?? true,
            episodeSortAscending: ud.object(forKey: "episodeSortAscending") as? Bool ?? true,
            enableHapticFeedback: ud.object(forKey: "enableHapticFeedback") as? Bool ?? false,
            hapticIntensity: ud.string(forKey: "hapticIntensity") ?? "medium",
            enableSoundFeedback: ud.object(forKey: "enableSoundFeedback") as? Bool ?? false,
            soundVolume: ud.object(forKey: "soundVolume") as? Double ?? 0.5,
            skipPlayedEpisodes: ud.object(forKey: "skipPlayedEpisodes") as? Bool ?? false,
            hidePlayedEpisodes: ud.object(forKey: "hidePlayedEpisodes") as? Bool ?? false
        )
    }

    private static func exportBranch(folder: Folder) -> ExportedFolderBranch {
        ExportedFolderBranch(
            name: folder.name,
            iconName: folder.iconName,
            sortOrder: folder.sortOrder,
            children: folder.sortedChildren.map { exportBranch(folder: $0) },
            assignedShowFeedURLs: folder.sortedShows.map(\.feedURL),
            folderEpisodeRefs: folder.sortedEpisodes.map {
                ExportedFolderEpisodeRef(showFeedURL: $0.show.feedURL, audioURL: $0.audioURL)
            }
        )
    }

    private static func folderPathNames(fromRootTo folder: Folder) -> [String] {
        var chain: [Folder] = []
        var f: Folder? = folder
        while let cur = f {
            chain.append(cur)
            f = cur.parent
        }
        return chain.reversed().dropFirst().map(\.name)
    }

    // MARK: - Import

    static func importLibrary(
        _ data: Data,
        context: ModelContext,
        languageSettings: LanguageSettings
    ) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(OsmPodLibraryExport.self, from: data)

        let parser = FeedParserService()

        for root in payload.rootFolders {
            try await insertFolderBranch(root, parent: nil, context: context, parser: parser)
        }

        for feed in payload.orphanShowFeedURLs {
            try await ensureShowRegistered(feedURL: feed, context: context, parser: parser)
        }

        for assign in payload.showAssignments {
            try await ensureShowRegistered(feedURL: assign.feedURL, context: context, parser: parser)
            guard let show = fetchShow(feedURL: assign.feedURL, context: context) else { continue }
            let folder = try resolveOrCreateFolder(path: assign.pathFromRoot, context: context, strings: languageSettings.strings)
            linkShow(show, to: folder)
        }

        for state in payload.episodeStates {
            guard let show = fetchShow(feedURL: state.showFeedURL, context: context),
                  let episode = show.episodes.first(where: { $0.audioURL == state.audioURL }) else { continue }
            episode.isPlayed = state.isPlayed
            episode.playbackPosition = state.playbackPosition
            if state.totalDuration > 0 { episode.totalDuration = state.totalDuration }
            episode.isNew = state.isNew
            episode.isFavorite = state.isFavorite
        }

        if let settings = payload.settings {
            applySettings(settings, languageSettings: languageSettings)
        }

        try context.save()
    }

    // MARK: - Cloud Sync helpers

    /// すべての番組・フォルダをエクスポートする（クラウド同期用）
    static func buildFullExportPayload(context: ModelContext) throws -> OsmPodLibraryExport {
        let allFolders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let allShows   = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        var payload = try buildExportPayload(
            selectedFolderIDs: Set(allFolders.map(\.persistentModelID)),
            selectedShowIDs:   Set(allShows.map(\.persistentModelID)),
            context: context
        )
        // Device preferences are intentionally excluded from iCloud synchronization.
        payload.settings = nil
        return payload
    }

    /// クラウドからダウンロードしたデータをマージインポートする。
    /// 設定（テーマ・言語など）はデバイス固有のため適用しない。
    static func syncImport(_ data: Data, context: ModelContext) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(OsmPodLibraryExport.self, from: data)
        let parser = FeedParserService()
        let strings = LocalizedStrings.current

        for root in payload.rootFolders {
            try await upsertFolderBranch(root, parent: nil, context: context, parser: parser)
        }

        for feed in payload.orphanShowFeedURLs {
            try await ensureShowRegistered(feedURL: feed, context: context, parser: parser)
        }

        for assign in payload.showAssignments {
            try await ensureShowRegistered(feedURL: assign.feedURL, context: context, parser: parser)
            guard let show = fetchShow(feedURL: assign.feedURL, context: context) else { continue }
            let folder = try resolveOrCreateFolder(path: assign.pathFromRoot, context: context, strings: strings)
            linkShow(show, to: folder)
        }

        for state in payload.episodeStates {
            guard let show = fetchShow(feedURL: state.showFeedURL, context: context),
                  let episode = show.episodes.first(where: { $0.audioURL == state.audioURL }) else { continue }
            episode.isPlayed = state.isPlayed
            episode.playbackPosition = state.playbackPosition
            if state.totalDuration > 0 { episode.totalDuration = state.totalDuration }
            episode.isNew = state.isNew
            episode.isFavorite = state.isFavorite
        }

        try context.save()
    }

    /// 同期用フォルダ upsert: 同名フォルダが同階層に存在すれば再利用し、なければ新規作成する。
    /// insertFolderBranch と異なり uniquifyFolderName を呼ばないため連番増殖が起きない。
    private static func upsertFolderBranch(
        _ branch: ExportedFolderBranch,
        parent: Folder?,
        context: ModelContext,
        parser: FeedParserService
    ) async throws {
        // 同名フォルダを探す
        let folder: Folder
        if let existing = findFolder(named: branch.name, parent: parent, context: context) {
            folder = existing
            folder.sortOrder = branch.sortOrder
            folder.iconName = branch.iconName
        } else {
            try PlanStore.shared.validateCanCreateFolder(context: context)
            folder = Folder(name: branch.name, iconName: branch.iconName, sortOrder: branch.sortOrder, parent: parent)
            context.insert(folder)
        }

        for feed in branch.assignedShowFeedURLs {
            try await ensureShowRegistered(feedURL: feed, context: context, parser: parser)
            if let show = fetchShow(feedURL: feed, context: context) {
                linkShow(show, to: folder)
            }
        }

        for ref in branch.folderEpisodeRefs {
            try await ensureShowRegistered(feedURL: ref.showFeedURL, context: context, parser: parser)
            guard let show = fetchShow(feedURL: ref.showFeedURL, context: context),
                  let episode = show.episodes.first(where: { $0.audioURL == ref.audioURL }) else { continue }
            if !episode.groups.contains(where: { $0.persistentModelID == folder.persistentModelID }) {
                episode.groups.append(folder)
                folder.episodes.append(episode)
            }
        }

        for child in branch.children {
            try await upsertFolderBranch(child, parent: folder, context: context, parser: parser)
        }
    }

    private static func findFolder(named name: String, parent: Folder?, context: ModelContext) -> Folder? {
        if let parent {
            return parent.sortedChildren.first(where: { $0.name == name })
        }
        let roots = (try? context.fetch(FetchDescriptor<Folder>()))?.filter(\.isRoot) ?? []
        return roots.first(where: { $0.name == name })
    }

    private static func applySettings(
        _ s: ExportedSettings,
        languageSettings: LanguageSettings
    ) {
        if let lang = AppLanguage(rawValue: s.language) { languageSettings.language = lang }
        AppSettings.shakeRewindSeconds = s.shakeRewindSeconds
        AppSettings.folderOrderOption = FolderOrderOption(rawValue: s.folderOrderOption) ?? .name
        AppSettings.episodeOrderOption = EpisodeOrderOption(rawValue: s.episodeOrderOption) ?? .date
        AppSettings.folderSortAscending = s.folderSortAscending
        AppSettings.episodeSortAscending = s.episodeSortAscending
        AppSettings.enableHapticFeedback = s.enableHapticFeedback
        AppSettings.hapticIntensity = HapticIntensity(rawValue: s.hapticIntensity) ?? .medium
        AppSettings.enableSoundFeedback = s.enableSoundFeedback
        AppSettings.soundVolume = s.soundVolume
        AppSettings.skipPlayedEpisodes = s.skipPlayedEpisodes
        AppSettings.hidePlayedEpisodes = s.hidePlayedEpisodes ?? false
    }

    // MARK: - Factory Reset

    /// ライブラリを消去し、設定を初期値へ戻したうえで、既定フォルダとサンプル番組を初回インストール相当まで復元する。
    static func resetToFactory(
        context: ModelContext,
        languageSettings: LanguageSettings,
        deleteCloudData: Bool
    ) async throws {
        try resetLibraryAndPreferences(
            context: context,
            languageSettings: languageSettings
        )
        deleteLocalFilesAndCaches()
        LocalFolderBookmarkStore.deleteAll()
        ShareImportStorage.clearPendingData()
        await ThumbnailImageCache.shared.deleteAll()
        if deleteCloudData {
            ICloudSyncManager.shared.deleteCloudData()
        }
        DefaultLibrarySeed.insertDefaultRootFoldersIfEmpty(context: context, strings: languageSettings.strings)
        try context.save()
    }

    /// `FavoriteFolderPin` → `Folder`、`Episode` → `Show` / `Folder` の参照があるため、batch の `delete(model:)` より明示削除が確実。
    private static func deleteEntireLibrary(context: ModelContext) throws {
        let pins = try context.fetch(FetchDescriptor<FavoriteFolderPin>())
        for pin in pins { context.delete(pin) }

        let episodes = try context.fetch(FetchDescriptor<Episode>())
        for episode in episodes { context.delete(episode) }

        let shows = try context.fetch(FetchDescriptor<Show>())
        for show in shows { context.delete(show) }

        let folders = try context.fetch(FetchDescriptor<Folder>())
        for root in folders where root.isRoot {
            context.delete(root)
        }

        try context.save()
    }

    private static func resetLibraryAndPreferences(
        context: ModelContext,
        languageSettings: LanguageSettings
    ) throws {
        try deleteEntireLibrary(context: context)

        let ud = UserDefaults.standard
        [
            "appLanguage", "osmPod.colorTheme", "osmPod.rowStyle",
            "osmPod.sceneCustom", "osmPod.sceneR", "osmPod.sceneG", "osmPod.sceneB",
            "dateFormat", "shakeRewindSeconds", "folderOrderOption", "episodeOrderOption",
            "folderSortAscending", "episodeSortAscending",
            "enableHapticFeedback", "hapticIntensity",
            "enableSoundFeedback", "soundVolume",
            "skipPlayedEpisodes", "hidePlayedEpisodes", "folderExpansionStates", "folderExpandedShows",
            "autoPlayEnabled", "autoPlayOrder", "autoPlayExcludedShowFeedURLs",
            "randomModeEnabled", "lastPlayingEpisodeAudioURL",
            "cloudSyncEnabled", "lastCloudSyncDate", "developerModeEnabled",
            ThirdPartyDataConsent.storageKey
        ].forEach { ud.removeObject(forKey: $0) }

        languageSettings.language = AppLanguage.defaultInstallLanguage
        AppSettings.shakeRewindSeconds = 15
        AppSettings.folderOrderOption = .name
        AppSettings.episodeOrderOption = .date
        AppSettings.folderSortAscending = true
        AppSettings.episodeSortAscending = true
        AppSettings.enableHapticFeedback = false
        AppSettings.hapticIntensity = .medium
        AppSettings.enableSoundFeedback = false
        AppSettings.soundVolume = 0.5
        AppSettings.skipPlayedEpisodes = false
        AppSettings.hidePlayedEpisodes = false
    }

    private static func deleteLocalFilesAndCaches() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        ["EpisodeDownloads", "LocalFileImports"].forEach {
            try? fm.removeItem(at: support.appendingPathComponent($0, isDirectory: true))
        }

        let temp = fm.temporaryDirectory
        if let entries = try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil) {
            for url in entries where
                url.lastPathComponent.hasPrefix("osmPod-")
                || url.lastPathComponent.hasPrefix("osmpod-") {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func insertFolderBranch(
        _ branch: ExportedFolderBranch,
        parent: Folder?,
        context: ModelContext,
        parser: FeedParserService
    ) async throws {
        try PlanStore.shared.validateCanCreateFolder(context: context)

        let sortOrder: Int
        if let parent {
            sortOrder = parent.sortedChildren.count
        } else {
            let roots = (try? context.fetch(FetchDescriptor<Folder>()))?.filter(\.isRoot) ?? []
            sortOrder = (roots.map(\.sortOrder).max() ?? -1) + 1
        }

        let folder = Folder(
            name: uniquifyFolderName(branch.name, parent: parent, context: context),
            iconName: branch.iconName,
            sortOrder: sortOrder,
            parent: parent
        )
        context.insert(folder)

        for feed in branch.assignedShowFeedURLs {
            try await ensureShowRegistered(feedURL: feed, context: context, parser: parser)
            if let show = fetchShow(feedURL: feed, context: context) {
                linkShow(show, to: folder)
            }
        }

        for ref in branch.folderEpisodeRefs {
            try await ensureShowRegistered(feedURL: ref.showFeedURL, context: context, parser: parser)
            guard let show = fetchShow(feedURL: ref.showFeedURL, context: context),
                  let episode = show.episodes.first(where: { $0.audioURL == ref.audioURL }) else { continue }
            if !episode.groups.contains(where: { $0.persistentModelID == folder.persistentModelID }) {
                episode.groups.append(folder)
                folder.episodes.append(episode)
            }
        }

        for child in branch.children {
            try await insertFolderBranch(child, parent: folder, context: context, parser: parser)
        }
    }

    private static func uniquifyFolderName(_ name: String, parent: Folder?, context: ModelContext) -> String {
        let siblings: [Folder]
        if let parent {
            siblings = parent.sortedChildren
        } else {
            siblings = (try? context.fetch(FetchDescriptor<Folder>()))?.filter(\.isRoot) ?? []
        }
        var candidate = name
        var n = 2
        while siblings.contains(where: { $0.name == candidate }) {
            candidate = "\(name) (\(n))"
            n += 1
        }
        return candidate
    }

    private static func resolveOrCreateFolder(path: [String], context: ModelContext, strings: LocalizedStrings) throws -> Folder {
        guard !path.isEmpty else {
            return try defaultImportFallbackFolder(context: context, strings: strings)
        }

        var parent: Folder? = nil
        for name in path {
            let matches: [Folder]
            if let p = parent {
                matches = p.sortedChildren.filter { $0.name == name }
            } else {
                matches = (try context.fetch(FetchDescriptor<Folder>())).filter { $0.isRoot && $0.name == name }
            }
            if let existing = matches.first {
                parent = existing
            } else {
                try PlanStore.shared.validateCanCreateFolder(context: context)
                let sortOrder: Int
                if let p = parent {
                    sortOrder = p.sortedChildren.count
                } else {
                    let roots = (try context.fetch(FetchDescriptor<Folder>())).filter(\.isRoot)
                    sortOrder = (roots.map(\.sortOrder).max() ?? -1) + 1
                }
                let f = Folder(name: name, iconName: "folder", sortOrder: sortOrder, parent: parent)
                context.insert(f)
                parent = f
            }
        }
        return parent!
    }

    private static func defaultImportFallbackFolder(context: ModelContext, strings: LocalizedStrings) throws -> Folder {
        let roots = try context.fetch(FetchDescriptor<Folder>()).filter(\.isRoot)
        if let first = roots.first { return first }
        try PlanStore.shared.validateCanCreateFolder(context: context)
        let f = Folder(name: strings.defaultFolderImport, iconName: "tray.and.arrow.down", sortOrder: 0)
        context.insert(f)
        return f
    }

    private static func fetchShow(feedURL: String, context: ModelContext) -> Show? {
        let d = FetchDescriptor<Show>(predicate: #Predicate { $0.feedURL == feedURL })
        return try? context.fetch(d).first
    }

    private static func ensureShowRegistered(feedURL: String, context: ModelContext, parser: FeedParserService) async throws {
        if fetchShow(feedURL: feedURL, context: context) != nil { return }
        try PlanStore.shared.validateCanRegisterShow(context: context)
        guard let url = URL(string: feedURL) else { return }
        let feed = try await parser.parse(feedURL: url)
        let show = parser.makeShow(from: feed, feedURL: url)
        context.insert(show)
        for ep in parser.makeEpisodes(from: feed, show: show) {
            // audioURL はグローバル unique 制約。他番組との重複を回避する。
            // #Predicate 内で @Model プロパティを直接参照すると KeyPath 解釈されるため、先にローカル変数へ取り出す。
            let audioURL = ep.audioURL
            let dup = FetchDescriptor<Episode>(predicate: #Predicate { $0.audioURL == audioURL })
            if (try? context.fetchCount(dup)) ?? 0 == 0 {
                context.insert(ep)
            }
        }
    }

    private static func linkShow(_ show: Show, to folder: Folder) {
        if folder.shows.contains(where: { $0.feedURL == show.feedURL }) { return }
        if show.groups.contains(where: { $0.persistentModelID == folder.persistentModelID }) { return }
        folder.shows.append(show)
        show.groups.append(folder)
    }

    // MARK: - Show metadata refresh

    /// Pull-to-refresh などで親タスクがキャンセルされると URLSession が `.cancelled` を返す。
    /// それを「番組の取得失敗」と誤カウントしない。
    private static func isRefreshAbortCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let feed = error as? FeedParseError, case .networkError(let inner) = feed {
            return isRefreshAbortCancellation(inner)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }

    static func refreshAllShows(context: ModelContext) async -> RefreshResult {
        let parser = FeedParserService()
        let strings = LocalizedStrings.current
        let allShows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        var refreshedShows = 0
        var updatedEpisodes = 0
        var addedEpisodes = 0
        var failedShows = 0

        for show in allShows {
            guard let url = URL(string: show.feedURL) else {
                failedShows += 1
                continue
            }
            // Local-file and registered-folder shows have no RSS feed to refresh.
            guard url.scheme != "local", url.scheme != "localfolder", url.scheme != "localfile" else { continue }

            do {
                let feed = try await parser.parse(feedURL: url)
                refreshedShows += 1

                // タイトルはユーザーが手入力で上書きしている可能性があるため保持する。
                // アートワークだけはフィード側の最新値を反映する。
                if let fetchedArtwork = feed.channel.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !fetchedArtwork.isEmpty {
                    show.artworkURL = fetchedArtwork
                }

                let existingByAudioURL = Dictionary(uniqueKeysWithValues: show.episodes.map { ($0.audioURL, $0) })
                for (index, item) in feed.episodes.enumerated() {
                    if let existing = existingByAudioURL[item.audioURL] {
                        existing.number = item.number
                        existing.title = strings.resolvedEpisodeTitle(item.title)
                        existing.publishedAt = item.publishedAt
                        existing.summary = item.summary
                        if let episodeArtwork = item.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !episodeArtwork.isEmpty {
                            existing.artworkURL = episodeArtwork
                        }
                        existing.sortOrder = index
                        updatedEpisodes += 1
                    } else {
                        let episode = Episode(
                            number: item.number,
                            title: strings.resolvedEpisodeTitle(item.title),
                            audioURL: item.audioURL,
                            artworkURL: item.artworkURL,
                            publishedAt: item.publishedAt,
                            summary: item.summary,
                            sortOrder: index,
                            show: show
                        )
                        context.insert(episode)
                        addedEpisodes += 1
                    }
                }
            } catch {
                if isRefreshAbortCancellation(error) {
                    // Pull-to-refresh 終了などでタスクがキャンセルされると各リクエストが失敗に見えるだけなので、失敗件数には含めない。
                    continue
                }
                failedShows += 1
            }
        }

        try? context.save()
        return RefreshResult(
            refreshedShows: refreshedShows,
            updatedEpisodes: updatedEpisodes,
            addedEpisodes: addedEpisodes,
            failedShows: failedShows
        )
    }

    // MARK: - Bulk delete

    static func deleteFolders(_ ids: Set<PersistentIdentifier>, context: ModelContext) throws {
        let desc = FetchDescriptor<Folder>()
        let all = (try? context.fetch(desc)) ?? []
        for folder in all where ids.contains(folder.persistentModelID) {
            context.delete(folder)
        }
        try context.save()
    }

    static func deleteShows(_ ids: Set<PersistentIdentifier>, context: ModelContext) throws {
        let desc = FetchDescriptor<Show>()
        let all = (try? context.fetch(desc)) ?? []
        for show in all where ids.contains(show.persistentModelID) {
            context.delete(show)
        }
        try context.save()
    }
}

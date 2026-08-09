import Foundation
import SwiftData

extension Episode {
    /// 再生中（🟡）または再生済み（🔵）になったらエピソードの新着🟢を外す。
    func clearNewIndicatorIfPlaybackEngaged() {
        guard playbackPosition > 0 || isPlayed else { return }
        // すでにクリア済みなら DB 更新・関連フラグ再計算をスキップ（5秒ごとの定期保存で呼ばれるため重要）。
        guard isNew else { return }
        isNew = false
        syncNewEpisodeIndicators()
    }

    /// 新着🟢を外し、番組・関連フォルダの新着フラグを再計算する。
    func clearNewIndicator() {
        isNew = false
        syncNewEpisodeIndicators()
    }

    /// 長押しメニューで「再生済み」を選んだとき。🔵表示・次回は保存位置から再生。
    func markAsPlayedManually() {
        isPlayed = true
        clearNewIndicatorIfPlaybackEngaged()
    }

    /// 長押しメニューで「未再生」を選んだとき。表示なし・次回は最初から再生。
    func markAsUnplayedManually() {
        isPlayed = false
        playbackPosition = 0
    }

    func syncNewEpisodeIndicators() {
        guard let context = modelContext else { return }
        let show = self.show
        let showFeedURL = show.feedURL
        let showHasNew = ((try? context.fetchCount(
            FetchDescriptor<Episode>(predicate: #Predicate { $0.isNewRaw == true && $0.show.feedURL == showFeedURL })
        )) ?? 0) > 0
        show.isNew = showHasNew
        for folder in foldersContainingEpisodeForNewIndicatorSync(show: show) {
            folder.isNew = folder.hasNewEpisodes
        }
    }

    /// `Episode.show` は to-one（FK）なので直接アクセスしてもフォルト解決は不要。
    static func containingShow(for episode: Episode, in context: ModelContext) -> Show? {
        episode.show
    }

    private func foldersContainingEpisodeForNewIndicatorSync(show: Show) -> [Folder] {
        var seen = Set<PersistentIdentifier>()
        var folders: [Folder] = []

        func add(_ folder: Folder) {
            let id = folder.persistentModelID
            guard seen.insert(id).inserted else { return }
            folders.append(folder)
            var parent = folder.parent
            while let ancestor = parent {
                let ancestorID = ancestor.persistentModelID
                if seen.insert(ancestorID).inserted {
                    folders.append(ancestor)
                }
                parent = ancestor.parent
            }
        }

        for folder in groups { add(folder) }
        for folder in show.groups { add(folder) }
        return folders
    }
}

extension Folder {
    var hasNewEpisodes: Bool {
        episodes.contains(where: \.isNew) || shows.contains(where: \.hasNewEpisodes) || children.contains(where: \.hasNewEpisodes)
    }

    /// フォルダ行のサムネイル用。配下の番組／エピソード／サブフォルダから代表画像 URL を探す。
    var representativeArtworkURL: String? {
        for s in sortedShows {
            if let u = s.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                return u
            }
        }
        for e in episodesSortedByOldest {
            if let u = e.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                return u
            }
            if let u = e.show.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                return u
            }
        }
        for c in sortedChildren {
            if let u = c.representativeArtworkURL { return u }
        }
        return nil
    }

    var sortedShows: [Show] {
        let asc = AppSettings.folderSortAscending
        switch AppSettings.folderOrderOption {
        case .name:
            return shows.sorted {
                let r = $0.title.localizedCaseInsensitiveCompare($1.title)
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
        case .date:
            return shows.sorted { asc ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        }
    }

    var sortedEpisodes: [Episode] {
        let asc = AppSettings.episodeSortAscending
        switch AppSettings.episodeOrderOption {
        case .name:
            return episodes.sorted {
                let r = $0.title.localizedCaseInsensitiveCompare($1.title)
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
        case .date:
            return episodes.sorted {
                let lhs = $0.publishedAt ?? .distantFuture
                let rhs = $1.publishedAt ?? .distantFuture
                if lhs != rhs { return asc ? lhs < rhs : lhs > rhs }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    var sortedChildren: [Folder] {
        FolderReorderService.orderedFolders(
            children,
            option: AppSettings.subfolderOrderOption,
            ascending: AppSettings.folderSortAscending
        )
    }

    private var episodesSortedByOldest: [Episode] {
        episodes.sorted {
            let lhs = $0.publishedAt ?? .distantFuture
            let rhs = $1.publishedAt ?? .distantFuture
            if lhs != rhs { return lhs < rhs }
            return $0.sortOrder < $1.sortOrder
        }
    }
}

extension Show {
    var hasNewEpisodes: Bool {
        episodes.contains(where: \.isNew)
    }

    var representativeArtworkURL: String? {
        if let showArtwork = artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines), !showArtwork.isEmpty {
            return showArtwork
        }
        for episode in sortedEpisodes {
            if let episodeArtwork = episode.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines), !episodeArtwork.isEmpty {
                return episodeArtwork
            }
        }
        return nil
    }

    var sortedEpisodes: [Episode] {
        let asc = AppSettings.episodeSortAscending
        return episodes.sorted {
            switch AppSettings.episodeOrderOption {
            case .name:
                let r = $0.title.localizedCaseInsensitiveCompare($1.title)
                return asc ? r == .orderedAscending : r == .orderedDescending
            case .date:
                let lhsDate = $0.publishedAt ?? .distantFuture
                let rhsDate = $1.publishedAt ?? .distantFuture
                if lhsDate != rhsDate { return asc ? lhsDate < rhsDate : lhsDate > rhsDate }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}

extension Collection where Element == Episode {
    func filteredForLibraryDisplay(hidePlayed: Bool) -> [Episode] {
        hidePlayed ? filter { !$0.isPlayed } : Array(self)
    }
}

// Recursively flattens a folder hierarchy into an ordered list with depth info.
extension [Folder] {
    func flattened(depth: Int = 0) -> [(folder: Folder, depth: Int)] {
        flatMap { folder in
            [(folder, depth)] + folder.sortedChildren.flattened(depth: depth + 1)
        }
    }
}

import SwiftUI
import SwiftData

/// ライブラリ一覧の新着🟢表示用。`Show` / `Folder` の `isNew` を `@Query` し、壊れた `Episode.show` 参照で落ちないようにする。
struct NewEpisodeIndicatorSnapshot: Equatable {
    var showIDs: Set<PersistentIdentifier> = []
    var folderIDs: Set<PersistentIdentifier> = []

    static let empty = NewEpisodeIndicatorSnapshot()

    static func build(newShows: [Show], newFolders: [Folder]) -> NewEpisodeIndicatorSnapshot {
        NewEpisodeIndicatorSnapshot(
            showIDs: Set(newShows.map(\.persistentModelID)),
            folderIDs: Set(newFolders.map(\.persistentModelID))
        )
    }
}

private struct NewEpisodeIndicatorEnvironmentKey: EnvironmentKey {
    static let defaultValue = NewEpisodeIndicatorSnapshot.empty
}

extension EnvironmentValues {
    var newEpisodeIndicators: NewEpisodeIndicatorSnapshot {
        get { self[NewEpisodeIndicatorEnvironmentKey.self] }
        set { self[NewEpisodeIndicatorEnvironmentKey.self] = newValue }
    }
}

enum NewEpisodeIndicatorSync {
    @MainActor
    static func refreshAll(in context: ModelContext) {
        repairOrphanedNewEpisodeFlags(in: context)

        // Use context.fetch with predicates to avoid to-many relationship fault resolution,
        // which crashes when called after an @MainActor async suspension point.
        let newEpisodes = (try? context.fetch(
            FetchDescriptor<Episode>(predicate: #Predicate { $0.isNewRaw == true })
        )) ?? []
        let showIDsWithNew = Set(newEpisodes.map { $0.show.persistentModelID })

        let allShows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        for show in allShows {
            show.isNew = showIDsWithNew.contains(show.persistentModelID)
        }
        try? context.save()

        // Query folders via SQL subquery predicates (no in-memory fault traversal).
        // Split into two fetches to keep each predicate simple for the type-checker.
        let foldersWithNewShows = (try? context.fetch(
            FetchDescriptor<Folder>(predicate: #Predicate { $0.shows.contains { $0.isNewRaw == true } })
        )) ?? []
        let foldersWithNewEpisodes = (try? context.fetch(
            FetchDescriptor<Folder>(predicate: #Predicate { $0.episodes.contains { $0.isNewRaw == true } })
        )) ?? []
        let newFolderIDs = Set(foldersWithNewShows.map(\.persistentModelID))
            .union(foldersWithNewEpisodes.map(\.persistentModelID))

        let allFolders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        for folder in allFolders {
            folder.isNew = newFolderIDs.contains(folder.persistentModelID)
        }
        try? context.save()
    }

    /// 新着フラグが立っているエピソードのうち、番組が削除済みのものをクリアする。
    /// `Episode.show` は to-one なので直接アクセスしてもフォルトは発生しない。
    private static func repairOrphanedNewEpisodeFlags(in context: ModelContext) {
        guard let flagged = try? context.fetch(
            FetchDescriptor<Episode>(predicate: #Predicate { $0.isNewRaw == true })
        ) else { return }
        let knownShowIDs = Set(
            (try? context.fetch(FetchDescriptor<Show>()))?.map(\.persistentModelID) ?? []
        )
        var repaired = false
        for episode in flagged where !knownShowIDs.contains(episode.show.persistentModelID) {
            episode.isNew = false
            repaired = true
        }
        if repaired { try? context.save() }
    }
}

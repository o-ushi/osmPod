import Foundation
import SwiftData

/// フォルダ⭐️と「お気に入り」内ショートカットの整合。
enum FavoriteFolderService {
    /// フラグ導入前に作られた「お気に入り」相当フォルダを拾い上げるための、言語別デフォルト名一覧。
    /// 通常の識別には使わず、`isFavoriteRoot` フラグが立っていない既存インストールの移行にのみ使う。
    private static var legacyFavoriteFolderNames: Set<String> {
        Set(AppLanguage.allCases.map { LocalizedStrings(language: $0).defaultFolderFavorites })
    }

    /// ルート直下の「お気に入り」フォルダ（なければ作成）。
    /// 表示名は言語ごとに異なるため、名前ではなく `Folder.isFavoriteRoot` フラグで識別する。
    @MainActor
    static func ensureFavoriteRootFolder(context: ModelContext) -> Folder {
        let roots = (try? context.fetch(FetchDescriptor<Folder>()))?.filter(\.isRoot) ?? []

        if let flagged = roots.first(where: { $0.isFavoriteRoot }) {
            return flagged
        }

        // 移行: フラグ導入前のインストールで作られた「お気に入り」フォルダに、名前一致で後付けする。
        if let legacy = roots.first(where: { legacyFavoriteFolderNames.contains($0.name) }) {
            legacy.isFavoriteRoot = true
            try? context.save()
            return legacy
        }

        let name = LocalizedStrings.current.defaultFolderFavorites
        guard PlanStore.shared.canCreateAnotherFolder(context: context) else {
            if let fallback = roots.first {
                return fallback
            }
            let folder = Folder(
                name: name,
                iconName: "star",
                sortOrder: 0,
                isFavoriteRootRaw: true
            )
            context.insert(folder)
            try? context.save()
            return folder
        }
        let maxSort = roots.map(\.sortOrder).max() ?? -1
        let folder = Folder(
            name: name,
            iconName: "star",
            sortOrder: maxSort + 1,
            isFavoriteRootRaw: true
        )
        context.insert(folder)
        try? context.save()
        return folder
    }

    static func isFavoriteLibrarySection(_ folder: Folder) -> Bool {
        folder.isRoot && (folder.isFavoriteRoot || legacyFavoriteFolderNames.contains(folder.name))
    }

    @MainActor
    static func sortedPinnedTargets(host: Folder, context: ModelContext) -> [Folder] {
        let pins = fetchPins(host: host, context: context)
        return pins.sorted { $0.sortOrder < $1.sortOrder }.map(\.target)
    }

    @MainActor
    static func toggleFavorite(folder: Folder, context: ModelContext) {
        let favoriteRoot = ensureFavoriteRootFolder(context: context)
        guard folder.persistentModelID != favoriteRoot.persistentModelID else { return }

        if folder.isFavorite {
            removePins(target: folder, host: favoriteRoot, context: context)
            folder.isFavorite = false
        } else {
            folder.isFavorite = true
            let order = fetchPins(host: favoriteRoot, context: context).count
            let pin = FavoriteFolderPin(sortOrder: order, host: favoriteRoot, target: folder)
            context.insert(pin)
        }
        try? context.save()
    }

    @MainActor
    static func removePinsInvolving(folder: Folder, context: ModelContext) {
        let fid = folder.persistentModelID
        let desc = FetchDescriptor<FavoriteFolderPin>(
            predicate: #Predicate<FavoriteFolderPin> { pin in
                pin.host.persistentModelID == fid || pin.target.persistentModelID == fid
            }
        )
        let pins = (try? context.fetch(desc)) ?? []
        for pin in pins {
            if pin.host.persistentModelID == fid {
                pin.target.isFavorite = false
            }
            context.delete(pin)
        }
    }

    @MainActor
    private static func fetchPins(host: Folder, context: ModelContext) -> [FavoriteFolderPin] {
        let hid = host.persistentModelID
        let desc = FetchDescriptor<FavoriteFolderPin>(
            predicate: #Predicate<FavoriteFolderPin> { pin in
                pin.host.persistentModelID == hid
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    @MainActor
    private static func removePins(target: Folder, host: Folder, context: ModelContext) {
        let tid = target.persistentModelID
        let hid = host.persistentModelID
        let desc = FetchDescriptor<FavoriteFolderPin>(
            predicate: #Predicate<FavoriteFolderPin> { pin in
                pin.host.persistentModelID == hid && pin.target.persistentModelID == tid
            }
        )
        (try? context.fetch(desc))?.forEach { context.delete($0) }
    }
}

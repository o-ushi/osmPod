import Foundation
import SwiftData

@Model
final class Folder {
    var name: String
    var iconName: String
    var sortOrder: Int
    var createdAt: Date
    var isFavoriteRaw: Bool?
    var isNewRaw: Bool?
    /// このフォルダが「お気に入り」特別ルートセクションかどうか。
    /// 表示名は言語ごとに異なる（"お気に入り"/"Favorites"/"Yêu thích"）ため、
    /// 名前文字列ではなくこのフラグで識別する（`FavoriteFolderService` 参照）。
    var isFavoriteRootRaw: Bool?

    var shows: [Show]
    var episodes: [Episode]

    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder]

    /// `FavoriteFolderPin` が `Folder` を2種類（host / target）参照するため、Core Data が区別できるよう `hashModifier` が必要。
    @Relationship(deleteRule: .cascade, inverse: \FavoriteFolderPin.host, hashModifier: "pinHost")
    var pinsWhereHost: [FavoriteFolderPin]

    @Relationship(deleteRule: .cascade, inverse: \FavoriteFolderPin.target, hashModifier: "pinTarget")
    var pinsWhereTarget: [FavoriteFolderPin]

    init(
        name: String,
        iconName: String = "folder",
        sortOrder: Int = 0,
        createdAt: Date = .now,
        isFavoriteRaw: Bool? = nil,
        isNewRaw: Bool? = nil,
        isFavoriteRootRaw: Bool? = nil,
        shows: [Show] = [],
        episodes: [Episode] = [],
        parent: Folder? = nil
    ) {
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isFavoriteRaw = isFavoriteRaw
        self.isNewRaw = isNewRaw
        self.isFavoriteRootRaw = isFavoriteRootRaw
        self.shows = shows
        self.episodes = episodes
        self.parent = parent
        self.children = []
        self.pinsWhereHost = []
        self.pinsWhereTarget = []
    }

    var isRoot: Bool { parent == nil }

    var displayPath: String {
        guard let parent else { return name }
        return "\(parent.displayPath) / \(name)"
    }

    var isFavorite: Bool {
        get { isFavoriteRaw ?? false }
        set { isFavoriteRaw = newValue }
    }

    var isNew: Bool {
        get { isNewRaw ?? false }
        set { isNewRaw = newValue }
    }

    var isFavoriteRoot: Bool {
        get { isFavoriteRootRaw ?? false }
        set { isFavoriteRootRaw = newValue }
    }
}

/// 「お気に入り」フォルダから別フォルダへジャンプするためのピン。
/// `Folder.pinsWhere*` 側の `@Relationship` の `inverse` が `host` / `target` を永続化する（ここに `@Relationship` を重ねると getter が二重になる）。
@Model
final class FavoriteFolderPin {
    var sortOrder: Int
    var host: Folder
    var target: Folder

    init(sortOrder: Int, host: Folder, target: Folder) {
        self.sortOrder = sortOrder
        self.host = host
        self.target = target
    }
}

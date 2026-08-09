import Foundation
import SwiftData

/// 初回インストールおよびデータ初期化後に、既定のルートフォルダだけを作成する。
enum DefaultLibrarySeed {
    @MainActor
    static func insertDefaultRootFoldersIfEmpty(context: ModelContext, strings: LocalizedStrings) {
        guard (try? context.fetchCount(FetchDescriptor<Folder>())) == 0 else { return }
        let defaults: [(name: String, icon: String, isFavoriteRoot: Bool)] = [
            (strings.defaultFolderFavorites, "star", true),
            (strings.defaultFolderListenLater, "clock", false),
            (strings.defaultFolderStudy, "book.closed", false),
        ]
        for (i, item) in defaults.enumerated() {
            context.insert(Folder(
                name: item.name,
                iconName: item.icon,
                sortOrder: i,
                isFavoriteRootRaw: item.isFavoriteRoot
            ))
        }
    }
}

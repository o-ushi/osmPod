import Foundation
import SwiftData

enum FolderMoveDirection {
    case up
    case down
}

enum FolderReorderService {
    /// トップレベルのフォルダは常に `sortOrder` で並べ替え。
    static func orderedRootFolders(_ folders: [Folder]) -> [Folder] {
        folders.filter(\.isRoot).sorted { $0.sortOrder < $1.sortOrder }
    }

    static func canReorder(_ folder: Folder) -> Bool {
        folder.isRoot
    }

    /// `Folder.children` を触らない並び替え（SwiftData モデルの nonisolated 文脈から呼べる）。
    static func orderedFolders(
        _ folders: [Folder],
        option: FolderOrderOption,
        ascending: Bool
    ) -> [Folder] {
        switch option {
        case .name:
            return folders.sorted {
                let r = $0.name.localizedCaseInsensitiveCompare($1.name)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .date:
            return folders.sorted { ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        }
    }

    @MainActor
    static func orderedChildren(
        of folder: Folder,
        option: FolderOrderOption,
        ascending: Bool
    ) -> [Folder] {
        orderedFolders(folder.children, option: option, ascending: ascending)
    }

    @MainActor
    static func canMove(
        _ folder: Folder,
        direction: FolderMoveDirection,
        context: ModelContext
    ) -> Bool {
        let siblings = orderedSiblings(of: folder, context: context)
        guard let index = siblings.firstIndex(where: { $0.persistentModelID == folder.persistentModelID }) else {
            return false
        }
        switch direction {
        case .up: return index > 0
        case .down: return index < siblings.count - 1
        }
    }

    @MainActor
    static func move(
        _ folder: Folder,
        direction: FolderMoveDirection,
        context: ModelContext
    ) {
        var siblings = orderedSiblings(of: folder, context: context)
        guard let index = siblings.firstIndex(where: { $0.persistentModelID == folder.persistentModelID }) else {
            return
        }
        let targetIndex = direction == .up ? index - 1 : index + 1
        guard siblings.indices.contains(targetIndex) else { return }

        siblings.swapAt(index, targetIndex)
        for (newIndex, sibling) in siblings.enumerated() {
            sibling.sortOrder = newIndex
        }
        try? context.save()
    }

    @MainActor
    private static func orderedSiblings(of folder: Folder, context: ModelContext) -> [Folder] {
        if let parent = folder.parent {
            return orderedFolders(
                parent.children,
                option: AppSettings.subfolderOrderOption,
                ascending: AppSettings.folderSortAscending
            )
        }
        return orderedRootFolders((try? context.fetch(FetchDescriptor<Folder>())) ?? [])
    }
}

extension Folder {
    var reorderToken: String {
        String(describing: persistentModelID)
    }
}

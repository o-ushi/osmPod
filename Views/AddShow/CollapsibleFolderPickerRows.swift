import SwiftUI
import SwiftData

/// 登録先フォルダ選択。サブフォルダは親の開閉で畳める。
struct CollapsibleFolderPickerRows: View {
    let roots: [Folder]
    @Binding var selectedFolder: Folder?

    @State private var expandedFolderIDs: Set<String> = []

    var body: some View {
        ForEach(roots) { root in
            FolderPickerNode(
                folder: root,
                depth: 0,
                selectedFolder: $selectedFolder,
                expandedFolderIDs: $expandedFolderIDs
            )
        }
    }
}

private struct FolderPickerNode: View {
    let folder: Folder
    let depth: Int
    @Binding var selectedFolder: Folder?
    @Binding var expandedFolderIDs: Set<String>

    private var folderStateID: String {
        "\(folder.displayPath)|\(folder.createdAt.timeIntervalSince1970)"
    }

    private var children: [Folder] { folder.sortedChildren }
    private var hasChildren: Bool { !children.isEmpty }
    private var isExpanded: Bool { expandedFolderIDs.contains(folderStateID) }

    var body: some View {
        Group {
            HStack(spacing: 4) {
                if hasChildren {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedFolderIDs.remove(folderStateID)
                            } else {
                                expandedFolderIDs.insert(folderStateID)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }

                GroupSelectionRow(
                    groupName: folder.name,
                    icon: folder.iconName,
                    depth: depth,
                    isSelected: selectedFolder?.persistentModelID == folder.persistentModelID
                ) {
                    selectedFolder = folder
                }
            }

            if hasChildren, isExpanded {
                ForEach(children) { child in
                    FolderPickerNode(
                        folder: child,
                        depth: depth + 1,
                        selectedFolder: $selectedFolder,
                        expandedFolderIDs: $expandedFolderIDs
                    )
                }
            }
        }
    }
}

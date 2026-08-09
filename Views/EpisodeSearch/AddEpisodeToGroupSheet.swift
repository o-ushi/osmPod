import SwiftUI
import SwiftData

struct AddEpisodeToGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang

    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    let episodes: [Episode]

    private var rootFolders: [Folder] { allFolders.filter(\.isRoot) }

    var body: some View {
        let s = lang.strings
        NavigationStack {
            List {
                ForEach(rootFolders.flattened(), id: \.folder.persistentModelID) { item in
                    GroupSelectionRow(
                        groupName: item.folder.name,
                        icon: item.folder.iconName,
                        depth: item.depth,
                        isSelected: allInFolder(item.folder)
                    ) {
                        toggleEpisodes(in: item.folder)
                    }
                }
            }
            .navigationTitle(navigationTitle(strings: s))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private func navigationTitle(strings s: LocalizedStrings) -> String {
        episodes.count == 1 ? s.addToFolder : s.addCountToFolderTitle(episodes.count)
    }

    private func allInFolder(_ folder: Folder) -> Bool {
        guard !episodes.isEmpty else { return false }
        return episodes.allSatisfy { episode in
            episode.groups.contains { $0.persistentModelID == folder.persistentModelID }
        }
    }

    @MainActor
    private func toggleEpisodes(in folder: Folder) {
        if allInFolder(folder) {
            for episode in episodes {
                episode.groups.removeAll { $0.persistentModelID == folder.persistentModelID }
                folder.episodes.removeAll { $0.persistentModelID == episode.persistentModelID }
            }
        } else {
            for episode in episodes {
                let alreadyIn = episode.groups.contains { $0.persistentModelID == folder.persistentModelID }
                if !alreadyIn {
                    episode.sortOrder = folder.episodes.count
                    episode.groups.append(folder)
                    folder.episodes.append(episode)
                }
            }
        }
        try? modelContext.save()
    }
}

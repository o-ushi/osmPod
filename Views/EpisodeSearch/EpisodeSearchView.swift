import SwiftUI
import SwiftData

struct EpisodeSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageSettings.self) private var lang

    @Query(sort: [
        SortDescriptor(\Episode.publishedAt, order: .reverse),
        SortDescriptor(\Episode.title)
    ])
    private var allEpisodes: [Episode]

    @State private var searchText = ""
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var isPresentingFolderPicker = false

    private var filteredEpisodes: [Episode] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return allEpisodes }
        return allEpisodes.filter {
            $0.title.lowercased().contains(query) ||
            $0.summary.lowercased().contains(query) ||
            $0.show.title.lowercased().contains(query)
        }
    }

    private var selectedEpisodes: [Episode] {
        allEpisodes.filter { selectedIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        let s = lang.strings
        NavigationStack {
            VStack(spacing: 0) {
                searchBar(s: s)
                Group {
                    if filteredEpisodes.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                s.noEpisodes,
                                systemImage: "waveform",
                                description: Text(s.noEpisodesDescription)
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else {
                        List(filteredEpisodes) { episode in
                            EpisodeSearchRowView(
                                episode: episode,
                                isSelected: selectedIDs.contains(episode.persistentModelID)
                            ) {
                                toggleSelection(of: episode)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(s.searchEpisodes)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Group {
                        Button {
                            isPresentingFolderPicker = true
                        } label: {
                            Label(
                                selectedIDs.isEmpty
                                    ? s.addToFolder
                                    : s.addCountToFolder(selectedIDs.count),
                                systemImage: "folder.badge.plus"
                            )
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                    .tint(AppPalette.textOnSubpagePrimary)
                }
                .osmPlainBackground()
            }
            .sheet(isPresented: $isPresentingFolderPicker, onDismiss: {
                selectedIDs.removeAll()
            }) {
                AddEpisodeToGroupSheet(episodes: selectedEpisodes)
            }
        }
    }

    /// キーワード検索欄と、選択状態を反映する閉じる/確定ボタン。
    /// ネイティブの `.searchable` は検索アクティブ中に独自ツールバーボタンを
    /// システムの「キャンセル」に差し替えてしまうため、常に選択状態を反映できるよう自前実装にしている。
    @ViewBuilder
    private func searchBar(s: LocalizedStrings) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(s.searchPrompt, text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                if selectedIDs.isEmpty {
                    dismiss()
                } else {
                    isPresentingFolderPicker = true
                }
            } label: {
                Image(systemName: selectedIDs.isEmpty ? "xmark" : "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6), in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func toggleSelection(of episode: Episode) {
        let id = episode.persistentModelID
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

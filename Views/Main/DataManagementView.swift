import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang
    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]
    @Query(sort: \Show.title) private var allShows: [Show]

    @State private var selectedFolderIDs: Set<PersistentIdentifier> = []
    @State private var selectedShowIDs: Set<PersistentIdentifier> = []
    @State private var exportShareItem: ExportSharePayload?
    @State private var isPresentingImporter = false
    @State private var exportFileName = "osmPod-library.json"
    @State private var importError: String?
    @State private var isImporting = false
    @State private var deleteConfirmPhase: DeletePhase?
    @State private var deleteCloudDataOnReset = false

    private enum DeletePhase {
        case folders
        case reset
    }

    private var rootFolders: [Folder] { allFolders.filter(\.isRoot) }

    var body: some View {
        let s = lang.strings
        List {
            Section {
                NavigationLink {
                    ShowManagementView()
                } label: {
                    Label(s.showManagementButton, systemImage: "rectangle.stack.badge.person.crop")
                }
            } footer: {
                Text(s.showManagementButtonFooter)
            }

            Section {
                Button {
                    prepareExport()
                } label: {
                    Label(s.exportSelected, systemImage: "square.and.arrow.up")
                }
                .disabled(selectedFolderIDs.isEmpty && selectedShowIDs.isEmpty)

                Button {
                    isPresentingImporter = true
                } label: {
                    Label(s.importJSON, systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)

                if isImporting {
                    HStack {
                        ProgressView()
                        Text(s.fetchingFeeds)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(role: .destructive) {
                    deleteConfirmPhase = .folders
                } label: {
                    Label(s.deleteFoldersBulk, systemImage: "folder.badge.minus")
                }
                .disabled(selectedFolderIDs.isEmpty)

                Button(role: .destructive) {
                    deleteConfirmPhase = .reset
                } label: {
                    Label(s.resetToPurchaseState, systemImage: "arrow.counterclockwise")
                }

                Toggle(
                    PrivacyText.text(
                        lang.language,
                        "Factory Reset時にiCloud同期データも削除",
                        "Also delete iCloud sync data on Factory Reset",
                        "Cũng xóa dữ liệu đồng bộ iCloud khi Factory Reset"
                    ),
                    isOn: $deleteCloudDataOnReset
                )
            } footer: {
                Text(s.dataManagementDeleteFooter)
            }

            Section {
                Button {
                    selectAll()
                } label: {
                    Label(s.selectAll, systemImage: "checkmark.circle")
                }
                .disabled(allFolders.isEmpty && allShows.isEmpty)

                Button {
                    clearSelection()
                } label: {
                    Label(s.deselectAll, systemImage: "circle")
                }
                .disabled(selectedFolderIDs.isEmpty && selectedShowIDs.isEmpty)
            }

            Section(s.foldersSection) {
                ForEach(rootFolders) { folder in
                    FolderSelectionOutline(folder: folder, depth: 0, selectedFolderIDs: $selectedFolderIDs)
                }
            }

            Section(s.showsSection) {
                ForEach(allShows) { show in
                    let checked = selectedShowIDs.contains(show.persistentModelID)
                    Button {
                        toggleShow(show)
                    } label: {
                        HStack(spacing: 12) {
                            ThumbnailArtworkView(
                                artworkURLString: show.representativeArtworkURL,
                                placeholderSystemImage: "dot.radiowaves.left.and.right"
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(show.title)
                                    .foregroundStyle(.primary)
                                Text(show.feedURL)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    checked
                                        ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(.secondary)
                                )
                        }
                    }
                }
            }

            if let importError {
                Section {
                    Text(importError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .osmSubpageListChrome()
        .navigationTitle(s.dataManagement)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportShareItem) { payload in
            ActivityShareController(activityItems: [payload.url])
                .presentationDetents([.medium, .large])
                .onDisappear {
                    try? FileManager.default.removeItem(at: payload.url)
                }
        }
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                await runImport(result)
            }
        }
        .confirmationDialog(
            deleteConfirmPhase == .reset ? s.resetToPurchaseState : s.confirmDelete,
            isPresented: Binding(
                get: { deleteConfirmPhase != nil },
                set: { if !$0 { deleteConfirmPhase = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteConfirmPhase == .reset ? s.resetToPurchaseState : s.delete, role: .destructive) {
                if deleteConfirmPhase == .folders {
                    try? LibraryImportExportService.deleteFolders(selectedFolderIDs, context: modelContext)
                    selectedFolderIDs.removeAll()
                } else if deleteConfirmPhase == .reset {
                    resetToPurchaseState()
                }
                deleteConfirmPhase = nil
            }
            Button(s.cancel, role: .cancel) {
                deleteConfirmPhase = nil
            }
        } message: {
            if deleteConfirmPhase == .folders {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.deleteFolderConfirm(selectedFolderIDs.count))
                    if ICloudSyncManager.shared.isEnabled {
                        Text(s.iCloudSyncDeletionRiskNote)
                    }
                }
            } else if deleteConfirmPhase == .reset {
                Text(s.resetToPurchaseStateMessage)
            }
        }
    }

    private func selectAll() {
        selectedFolderIDs = Set(allFolders.map(\.persistentModelID))
        selectedShowIDs = Set(allShows.map(\.persistentModelID))
    }

    private func clearSelection() {
        selectedFolderIDs.removeAll()
        selectedShowIDs.removeAll()
    }

    private func resetToPurchaseState() {
        Task { @MainActor in
            importError = nil
            do {
                try await LibraryImportExportService.resetToFactory(
                    context: modelContext,
                    languageSettings: lang,
                    deleteCloudData: deleteCloudDataOnReset
                )
                selectedFolderIDs.removeAll()
                selectedShowIDs.removeAll()
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func toggleShow(_ show: Show) {
        let id = show.persistentModelID
        if selectedShowIDs.contains(id) {
            selectedShowIDs.remove(id)
        } else {
            selectedShowIDs.insert(id)
        }
    }

    private func prepareExport() {
        do {
            let payload = try LibraryImportExportService.buildExportPayload(
                selectedFolderIDs: selectedFolderIDs,
                selectedShowIDs: selectedShowIDs,
                context: modelContext
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let stamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
            exportFileName = "osmPod-\(stamp).json"

            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName)
            try data.write(to: temp, options: .atomic)
            exportShareItem = ExportSharePayload(url: temp)
        } catch {
            importError = error.localizedDescription
        }
    }

    @MainActor
    private func runImport(_ result: Result<[URL], Error>) async {
        importError = nil
        switch result {
        case .failure(let e):
            importError = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            defer { isImporting = false }
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                try await LibraryImportExportService.importLibrary(
                    data,
                    context: modelContext,
                    languageSettings: lang
                )
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

// MARK: - Duplicate Show Merge

@MainActor
enum ShowDuplicateMergeService {
    struct MergeResult {
        let keptShowTitle: String
        let removedShowCount: Int
        let movedEpisodeCount: Int
        let removedDuplicateEpisodeCount: Int
    }

    struct DuplicateGroup: Identifiable {
        var id: String { title }
        let title: String
        let shows: [Show]
    }

    static func duplicateGroups(from shows: [Show]) -> [DuplicateGroup] {
        var grouped: [String: [Show]] = [:]
        for show in shows {
            grouped[show.title, default: []].append(show)
        }
        return grouped
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(title: $0.key, shows: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @discardableResult
    static func mergeAllDuplicateGroups(in shows: [Show], context: ModelContext) throws -> [MergeResult] {
        var results: [MergeResult] = []
        for group in duplicateGroups(from: shows) {
            if let result = try mergeShows(group.shows, context: context) {
                results.append(result)
            }
        }
        return results
    }

    @discardableResult
    static func mergeShows(_ shows: [Show], context: ModelContext) throws -> MergeResult? {
        guard shows.count > 1 else { return nil }

        let sorted = shows.sorted { lhs, rhs in
            if lhs.episodes.count != rhs.episodes.count {
                return lhs.episodes.count > rhs.episodes.count
            }
            return lhs.createdAt < rhs.createdAt
        }
        guard let keeper = sorted.first else { return nil }
        let duplicates = Array(sorted.dropFirst())

        var existingAudioURLs = Set(keeper.episodes.map(\.audioURL))
        var contentKeys = Dictionary(uniqueKeysWithValues: keeper.episodes.map { (episodeContentKey($0), $0) })
        var moved = 0
        var removedEpisodes = 0
        var removedFeedURLs: [String] = []

        for duplicate in duplicates {
            removedFeedURLs.append(duplicate.feedURL)

            for episode in Array(duplicate.episodes) {
                let contentKey = episodeContentKey(episode)

                if existingAudioURLs.contains(episode.audioURL) {
                    context.delete(episode)
                    deleteEpisodeBookmarkIfNeeded(for: episode)
                    removedEpisodes += 1
                    continue
                }

                if let existing = contentKeys[contentKey] {
                    mergeEpisodeState(from: episode, into: existing)
                    context.delete(episode)
                    deleteEpisodeBookmarkIfNeeded(for: episode)
                    removedEpisodes += 1
                    continue
                }

                episode.show = keeper
                existingAudioURLs.insert(episode.audioURL)
                contentKeys[contentKey] = episode
                moved += 1
            }

            unlinkShowFromFolders(duplicate)
            deleteShowBookmarkIfNeeded(for: duplicate)
            context.delete(duplicate)
        }

        normalizeSortOrders(for: keeper)
        reconcileAutoPlayExclusions(removedFeedURLs: removedFeedURLs, keeperFeedURL: keeper.feedURL)
        try context.save()
        NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)

        return MergeResult(
            keptShowTitle: keeper.title,
            removedShowCount: duplicates.count,
            movedEpisodeCount: moved,
            removedDuplicateEpisodeCount: removedEpisodes
        )
    }

    private static func episodeContentKey(_ episode: Episode) -> String {
        let url = episode.audioURL
        if url.hasPrefix("localfolder://") {
            if let filename = url.split(separator: "/").last {
                return "file:\(filename.lowercased())"
            }
        }
        if url.hasPrefix("localfile://") {
            return "title:\(episode.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }
        return "url:\(url)"
    }

    private static func mergeEpisodeState(from source: Episode, into target: Episode) {
        if source.playbackPosition > target.playbackPosition {
            target.playbackPosition = source.playbackPosition
        }
        if source.isPlayed { target.isPlayed = true }
        if source.isFavorite { target.isFavorite = true }
        if source.totalDuration > target.totalDuration {
            target.totalDuration = source.totalDuration
        }
        if target.downloadedAudioPath == nil {
            target.downloadedAudioPath = source.downloadedAudioPath
        }
    }

    private static func normalizeSortOrders(for show: Show) {
        let ordered = show.episodes.sorted {
            let lhsDate = $0.publishedAt ?? .distantPast
            let rhsDate = $1.publishedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        for (index, episode) in ordered.enumerated() {
            episode.sortOrder = index
        }
    }

    private static func unlinkShowFromFolders(_ show: Show) {
        for folder in show.groups {
            folder.shows.removeAll { $0.persistentModelID == show.persistentModelID }
        }
        show.groups.removeAll()
    }

    private static func reconcileAutoPlayExclusions(removedFeedURLs: [String], keeperFeedURL: String) {
        var excluded = AppSettings.autoPlayExcludedShowFeedURLs
        let removed = Set(removedFeedURLs)
        let shouldStayExcluded = !excluded.isDisjoint(with: removed)
        excluded.subtract(removed)
        if shouldStayExcluded {
            excluded.insert(keeperFeedURL)
        }
        AppSettings.autoPlayExcludedShowFeedURLs = excluded
    }

    private static func deleteShowBookmarkIfNeeded(for show: Show) {
        if show.feedURL.hasPrefix("localfolder://") {
            let key = String(show.feedURL.dropFirst("localfolder://".count))
            LocalFolderBookmarkStore.delete(for: key)
        }
    }

    private static func deleteEpisodeBookmarkIfNeeded(for episode: Episode) {
        guard episode.audioURL.hasPrefix("localfile://") else { return }
        let key = String(episode.audioURL.dropFirst("localfile://".count))
        guard !key.hasPrefix("show/"), !key.isEmpty else { return }
        LocalFolderBookmarkStore.delete(for: key)
    }
}

// MARK: - Show Management

struct ShowManagementView: View {
    @Environment(LanguageSettings.self) private var lang
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Show.title)]) private var shows: [Show]
    @State private var showToDelete: Show?
    @State private var mergeTarget: ShowDuplicateMergeService.DuplicateGroup?
    @State private var mergeAllConfirm = false
    @State private var mergeResultMessage: String?

    private var duplicateGroups: [ShowDuplicateMergeService.DuplicateGroup] {
        ShowDuplicateMergeService.duplicateGroups(from: shows)
    }

    private var duplicateTitles: Set<String> {
        Set(duplicateGroups.map(\.title))
    }

    var body: some View {
        let s = lang.strings
        let dupes = duplicateTitles
        List {
            if !duplicateGroups.isEmpty {
                Section {
                    ForEach(duplicateGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.headline)

                            ForEach(group.shows) { show in
                                ShowDuplicateCandidateRow(show: show, strings: s)
                            }

                            Button {
                                mergeTarget = group
                            } label: {
                                Label(s.showManagementMergeButton, systemImage: "arrow.triangle.merge")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        mergeAllConfirm = true
                    } label: {
                        Label(s.showManagementMergeAllButton, systemImage: "arrow.triangle.merge")
                    }
                } header: {
                    Text(s.showManagementDuplicateGroupsSection)
                } footer: {
                    Text(s.showManagementDuplicateCount(shows.filter { dupes.contains($0.title) }.count))
                }
            }

            Section {
                if shows.isEmpty {
                    Text(s.showManagementNoShows)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shows) { show in
                        ShowManagementRow(
                            show: show,
                            isDuplicate: dupes.contains(show.title),
                            onDelete: { showToDelete = show }
                        )
                    }
                }
            } header: {
                Text(s.showsSectionWithCount(shows.count))
            }
        }
        .osmSubpageListChrome()
        .navigationTitle(s.showManagementTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            s.confirmDelete,
            isPresented: Binding(get: { showToDelete != nil }, set: { if !$0 { showToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let show = showToDelete {
                Button(s.delete, role: .destructive) {
                    modelContext.delete(show)
                    try? modelContext.save()
                    showToDelete = nil
                }
            }
            Button(s.cancel, role: .cancel) { showToDelete = nil }
        } message: {
            if let show = showToDelete {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.showManagementDeleteConfirm(show.title))
                    if ICloudSyncManager.shared.isEnabled {
                        Text(s.iCloudSyncDeletionRiskNote)
                    }
                }
            }
        }
        .confirmationDialog(
            s.showManagementMergeButton,
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let group = mergeTarget {
                Button(s.showManagementMergeButton) {
                    mergeGroup(group)
                    mergeTarget = nil
                }
            }
            Button(s.cancel, role: .cancel) { mergeTarget = nil }
        } message: {
            if let group = mergeTarget {
                Text(s.showManagementMergeGroupConfirm(group.title))
            }
        }
        .confirmationDialog(
            s.showManagementMergeAllButton,
            isPresented: $mergeAllConfirm,
            titleVisibility: .visible
        ) {
            Button(s.showManagementMergeAllButton) {
                mergeAllGroups()
            }
            Button(s.cancel, role: .cancel) {}
        } message: {
            Text(s.showManagementMergeAllConfirm)
        }
        .alert(s.showManagementMergeResultTitle, isPresented: Binding(
            get: { mergeResultMessage != nil },
            set: { if !$0 { mergeResultMessage = nil } }
        )) {
            Button(s.ok) { mergeResultMessage = nil }
        } message: {
            Text(mergeResultMessage ?? "")
        }
    }

    private func mergeGroup(_ group: ShowDuplicateMergeService.DuplicateGroup) {
        do {
            if let result = try ShowDuplicateMergeService.mergeShows(group.shows, context: modelContext) {
                mergeResultMessage = lang.strings.showManagementMergeResult(
                    result.keptShowTitle,
                    removedShows: result.removedShowCount,
                    moved: result.movedEpisodeCount,
                    removedEpisodes: result.removedDuplicateEpisodeCount
                )
            }
        } catch {
            mergeResultMessage = lang.strings.showManagementMergeFailed(error.localizedDescription)
        }
    }

    private func mergeAllGroups() {
        do {
            let results = try ShowDuplicateMergeService.mergeAllDuplicateGroups(in: shows, context: modelContext)
            mergeResultMessage = lang.strings.showManagementMergeAllResult(results.count)
        } catch {
            mergeResultMessage = lang.strings.showManagementMergeFailed(error.localizedDescription)
        }
    }
}

private struct ShowDuplicateCandidateRow: View {
    let show: Show
    let strings: LocalizedStrings

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailArtworkView(
                artworkURLString: show.representativeArtworkURL,
                placeholderSystemImage: "dot.radiowaves.left.and.right"
            )
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(strings.showManagementEpisodeCount(show.episodes.count))
                    .font(.subheadline)
                Text(strings.showManagementRegisteredAt(show.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(strings.showManagementFeedSource(show.feedURL))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ShowManagementRow: View {
    @Environment(LanguageSettings.self) private var lang
    let show: Show
    let isDuplicate: Bool
    let onDelete: () -> Void

    var body: some View {
        let s = lang.strings
        HStack(spacing: 12) {
            ThumbnailArtworkView(
                artworkURLString: show.representativeArtworkURL,
                placeholderSystemImage: "dot.radiowaves.left.and.right"
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(show.title)
                        .foregroundStyle(.primary)
                    if isDuplicate {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(s.showManagementDuplicateRowHint)
                    }
                }
                Text(s.showManagementFeedSource(show.feedURL))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(s.showManagementEpisodeCount(show.episodes.count))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Export share sheet

private struct ExportSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareController: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Recursive folder selection rows

private struct FolderSelectionOutline: View {
    let folder: Folder
    let depth: Int
    @Binding var selectedFolderIDs: Set<PersistentIdentifier>

    var body: some View {
        let checked = selectedFolderIDs.contains(folder.persistentModelID)
        Button {
            if checked {
                selectedFolderIDs.remove(folder.persistentModelID)
            } else {
                selectedFolderIDs.insert(folder.persistentModelID)
            }
        } label: {
            HStack(spacing: 12) {
                Color.clear.frame(width: CGFloat(depth * 14))
                ThumbnailArtworkView(
                    artworkURLString: folder.representativeArtworkURL,
                    placeholderSystemImage: folder.iconName
                )
                Text(folder.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        checked
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(.secondary)
                    )
            }
        }
        ForEach(folder.sortedChildren) { child in
            FolderSelectionOutline(folder: child, depth: depth + 1, selectedFolderIDs: $selectedFolderIDs)
        }
    }
}

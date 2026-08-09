import SwiftUI
import SwiftData

/// フォルダ直下の並び替え結果をキャッシュ（スクロール中の毎フレーム sort を避ける）。
private struct FolderListCache {
    var children: [Folder] = []
    var shows: [Show] = []
    var episodes: [Episode] = []

    static func make(for folder: Folder) -> FolderListCache {
        FolderListCache(
            children: folder.sortedChildren,
            shows: folder.sortedShows,
            episodes: folder.sortedEpisodes
        )
    }
}

/// 直下のエピソード／番組だけを見る（子フォルダは各行が自分で表示する）。
private func folderHasDirectInProgressEpisode(_ folder: Folder) -> Bool {
    if folder.episodes.contains(where: { $0.playbackPosition > 0 && !$0.isPlayed }) { return true }
    return folder.shows.contains { show in
        show.episodes.contains { $0.playbackPosition > 0 && !$0.isPlayed }
    }
}

private enum GroupSheet: Identifiable {
    case editFolder
    case addSubfolder
    case episodePicker(Show)
    case editEpisode(Episode)

    var id: String {
        switch self {
        case .editFolder:              return "edit"
        case .addSubfolder:            return "addSubfolder"
        case .episodePicker(let show): return "episodePicker-\(show.feedURL)"
        case .editEpisode(let episode): return "editEpisode-\(episode.audioURL)"
        }
    }
}

private extension View {
    func swipeTrailingActions(
        buttonWidth: CGFloat = 72,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(TrailingSwipeActionsModifier(buttonWidth: buttonWidth, onEdit: onEdit, onDelete: onDelete))
    }

    func swipeEditDelete(
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        swipeTrailingActions(onEdit: onEdit, onDelete: onDelete)
    }
}

private struct TrailingSwipeActionsModifier: ViewModifier {
    let buttonWidth: CGFloat
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var openOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0

    private var totalWidth: CGFloat { buttonWidth * 2 }

    private var rowDragGesture: some Gesture {
        DragGesture(minimumDistance: 36)
            .onChanged { value in
                let w = value.translation.width
                let h = value.translation.height
                guard abs(w) > abs(h) * 2.5 else {
                    dragOffset = 0
                    return
                }
                if openOffset < 0 {
                    dragOffset = max(0, w)
                } else {
                    dragOffset = min(0, w)
                }
            }
            .onEnded { value in
                defer { dragOffset = 0 }
                let w = value.translation.width
                let h = value.translation.height
                guard abs(w) > abs(h) * 2.5 else { return }
                withAnimation(.spring(response: 0.28)) {
                    let projected = openOffset + w
                    if openOffset < 0 {
                        openOffset = (w > 32 || projected > -totalWidth / 2) ? 0 : -totalWidth
                    } else {
                        openOffset = (w < -32 || projected < -totalWidth / 2) ? -totalWidth : 0
                    }
                }
            }
    }

    func body(content: Content) -> some View {
        let effectiveOffset = clampedOffset(openOffset + dragOffset)
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.25)) { openOffset = 0 }
                    HapticManager.shared.provideFeedback()
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: buttonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                }
                .buttonStyle(.borderless)

                Button {
                    withAnimation(.spring(response: 0.25)) { openOffset = 0 }
                    HapticManager.shared.provideFeedback()
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: buttonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.gray)
                }
                .buttonStyle(.borderless)
            }

            content
                .background(AppPalette.cardFill)
                .offset(x: effectiveOffset)
                .allowsHitTesting(openOffset == 0)
        }
        .overlay(alignment: .leading) {
            if openOffset != 0 {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, totalWidth)
            }
        }
        .simultaneousGesture(rowDragGesture)
        .clipped()
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        min(0, max(-totalWidth, value))
    }
}

private let episodeJumpBarThreshold = 10

private struct ExpandedEpisodeListSection: View {
    @Environment(LanguageSettings.self) private var lang
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(EpisodeListJumpCoordinator.self) private var jumpCoordinator
    @Environment(\.modelContext) private var modelContext

    let jumpContextID: String
    let episodes: [Episode]
    let queueContext: PlaybackQueueContext
    let onEdit: (Episode) -> Void
    let onDelete: (Episode) -> Void

    private var jumpRegistrationToken: String {
        "\(episodes.count)|\(episodes.first?.audioURL ?? "")|\(episodes.last?.audioURL ?? "")"
    }

    var body: some View {
        Group {
            if episodes.isEmpty {
                Text(lang.strings.noVisibleEpisodes)
                    .font(.caption)
                    .foregroundStyle(AppPalette.textOnCardSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ForEach(episodes) { episode in
                    Divider().padding(.leading, 16)
                    EpisodeRowView(episode: episode, isOnCard: true) {
                        audioPlayer.play(
                            episode: episode,
                            context: modelContext,
                            queueContext: queueContext
                        )
                    }
                    .padding(.horizontal, 16)
                    .id(EpisodeScrollAnchor.id(for: episode))
                    .swipeEditDelete(
                        onEdit: { onEdit(episode) },
                        onDelete: { onDelete(episode) }
                    )
                }
            }
        }
        .onAppear { syncJumpBarRegistration() }
        .onDisappear { jumpCoordinator.unregister(id: jumpContextID) }
        .onChange(of: jumpRegistrationToken) { _, _ in syncJumpBarRegistration() }
    }

    private func syncJumpBarRegistration() {
        guard episodes.count >= episodeJumpBarThreshold,
              let top = episodes.first,
              let bottom = episodes.last else {
            jumpCoordinator.unregister(id: jumpContextID)
            return
        }
        jumpCoordinator.register(
            EpisodeListJumpCoordinator.Context(
                id: jumpContextID,
                topAudioURL: top.audioURL,
                bottomAudioURL: bottom.audioURL
            )
        )
    }
}

// MARK: - GroupSectionView

struct GroupSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LanguageSettings.self) private var lang
    @Environment(\.newEpisodeIndicators) private var newEpisodeIndicators
    let folder: Folder

    @AppStorage("folderOrderOption") private var folderOrderKey = FolderOrderOption.name.rawValue
    @AppStorage("folderSortAscending") private var folderSortAscending = true
    @AppStorage("episodeOrderOption") private var episodeOrderKey = EpisodeOrderOption.date.rawValue
    @AppStorage("episodeSortAscending") private var episodeSortAscending = true
    @AppStorage("hidePlayedEpisodes") private var hidePlayedEpisodes = false

    @State private var activeSheet: GroupSheet? = nil
    @State private var isDragTargeted = false
    @State private var expandedShows: Set<String> = []
    @State private var isSectionExpanded = true
    @State private var didRestoreState = false
    @State private var listCache = FolderListCache()
    @State private var pinnedShortcutTargets: [Folder] = []
    private let newEpisodeIndicatorColor = Color(red: 0.67, green: 0.9, blue: 0.25)

    private var folderStateID: String {
        "\(folder.displayPath)|\(folder.createdAt.timeIntervalSince1970)"
    }

    var body: some View {
        VStack(spacing: 0) {
            folderHeaderRow

            if isSectionExpanded {
                if FavoriteFolderService.isFavoriteLibrarySection(folder) {
                    ForEach(pinnedShortcutTargets, id: \.persistentModelID) { target in
                        Divider().padding(.leading, 16)
                        GroupSectionView(folder: target)
                            .padding(.leading, 8)
                    }
                }

                ForEach(listCache.children) { child in
                    Divider().padding(.leading, 16)
                    SubfolderRowView(folder: child, expandedShows: $expandedShows)
                }

                ForEach(listCache.shows) { show in
                    Divider().padding(.leading, 16)
                    showInFolderRow(show: show)
                }

                if !visibleFolderEpisodes.isEmpty {
                    Divider().padding(.leading, 16)
                    ExpandedEpisodeListSection(
                        jumpContextID: "\(folderStateID)-episodes",
                        episodes: visibleFolderEpisodes,
                        queueContext: .folder(folder.persistentModelID),
                        onEdit: { activeSheet = .editEpisode($0) },
                        onDelete: { removeEpisodeFromFolder($0) }
                    )
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12).fill(AppPalette.cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppPalette.cardBorder, lineWidth: AppPalette.cardBorderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .onAppear {
            refreshListCache()
            guard !didRestoreState else { return }
            isSectionExpanded = AppSettings.isFolderExpanded(folderID: folderStateID, defaultValue: true)
            expandedShows = AppSettings.expandedShowIDs(folderID: folderStateID)
            didRestoreState = true
        }
        .onChange(of: folderOrderKey) { _, _ in refreshListCache() }
        .onChange(of: folderSortAscending) { _, _ in refreshListCache() }
        .onChange(of: episodeOrderKey) { _, _ in refreshListCache() }
        .onChange(of: episodeSortAscending) { _, _ in refreshListCache() }
        .onChange(of: folder.shows.count) { _, _ in refreshListCache() }
        .onChange(of: folder.episodes.count) { _, _ in refreshListCache() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryContentDidChange)) { _ in
            refreshListCache()
        }
        .onChange(of: isSectionExpanded) { _, newValue in
            AppSettings.setFolderExpanded(newValue, folderID: folderStateID)
        }
        .onChange(of: expandedShows) { _, newValue in
            AppSettings.setExpandedShowIDs(newValue, folderID: folderStateID)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editFolder:
                FolderEditView(folder: folder)
            case .addSubfolder:
                FolderEditView(parentFolder: folder)
            case .episodePicker(let show):
                ShowEpisodePickerView(show: show)
            case .editEpisode(let episode):
                AddEpisodeToGroupSheet(episodes: [episode])
            }
        }
    }

    private var folderContainsInProgressEpisode: Bool {
        folderHasDirectInProgressEpisode(folder)
    }

    private func refreshListCache() {
        listCache = FolderListCache.make(for: folder)
        if FavoriteFolderService.isFavoriteLibrarySection(folder) {
            pinnedShortcutTargets = FavoriteFolderService.sortedPinnedTargets(host: folder, context: modelContext)
        } else {
            pinnedShortcutTargets = []
        }
    }

    private var visibleFolderEpisodes: [Episode] {
        listCache.episodes.filteredForLibraryDisplay(hidePlayed: hidePlayedEpisodes)
    }

    private func visibleShowEpisodes(_ show: Show) -> [Episode] {
        show.sortedEpisodes.filteredForLibraryDisplay(hidePlayed: hidePlayedEpisodes)
    }

    private var folderHeaderRow: some View {
        let hasPinnedShortcuts =
            FavoriteFolderService.isFavoriteLibrarySection(folder)
            && !pinnedShortcutTargets.isEmpty
        let hasChildren =
            hasPinnedShortcuts ||
            !listCache.children.isEmpty ||
            !listCache.shows.isEmpty ||
            !listCache.episodes.isEmpty

        return HStack(spacing: 12) {
            ThumbnailArtworkView(
                artworkURLString: folder.representativeArtworkURL,
                placeholderSystemImage: folder.iconName
            )

            Text(folder.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.textOnCardPrimary)
            if newEpisodeIndicators.folderIDs.contains(folder.persistentModelID) {
                Circle()
                    .fill(newEpisodeIndicatorColor)
                    .frame(width: 8, height: 8)
            }

            Spacer(minLength: 8)

            if hasChildren {
                HStack(spacing: 4) {
                    if folderContainsInProgressEpisode {
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                    }
                    Image(systemName: isSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.textOnCardSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isDragTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppPalette.cardAccent)
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { payloads, _ in
            payloads.forEach { moveShow(payload: $0, to: folder) }
            return true
        } isTargeted: { isDragTargeted = $0 }
        .folderRowContextMenu(
            folder: folder,
            strings: lang.strings,
            modelContext: modelContext,
            onAddSubfolder: { activeSheet = .addSubfolder },
            onReordered: { refreshListCache() }
        )
        .onTapGesture {
            guard hasChildren else { return }
            HapticManager.shared.provideFeedback()
            withAnimation(.easeInOut(duration: 0.2)) {
                isSectionExpanded.toggle()
            }
        }
        .swipeEditDelete(
            onEdit: { activeSheet = .editFolder },
            onDelete: { deleteFolder() }
        )
    }

    @ViewBuilder
    private func showInFolderRow(show: Show) -> some View {
        let isExpanded = expandedShows.contains(show.feedURL)
        let visibleEpisodes = visibleShowEpisodes(show)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    ThumbnailArtworkView(
                        artworkURLString: show.representativeArtworkURL,
                        placeholderSystemImage: "dot.radiowaves.left.and.right"
                    )
                    ShowRowView(
                        show: show,
                        showsNewEpisodeIndicator: newEpisodeIndicators.showIDs.contains(show.persistentModelID)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .draggable("\(show.feedURL)\t\(folder.name)")
                .contextMenu {
                    Button(lang.strings.episodeList, systemImage: "list.bullet") {
                        HapticManager.shared.provideFeedback()
                        activeSheet = .episodePicker(show)
                    }
                    Divider()
                    Button(lang.strings.removeFromFolder, systemImage: "trash", role: .destructive) {
                        HapticManager.shared.provideFeedback()
                        removeShowFromFolder(show)
                    }
                }

                if !visibleEpisodes.isEmpty {
                    let showHasInProgress = show.episodes.contains {
                        $0.playbackPosition > 0 && !$0.isPlayed
                    }
                    HStack(spacing: 4) {
                        if showHasInProgress {
                            Circle().fill(Color.yellow).frame(width: 8, height: 8)
                        }
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.textOnCardSecondary)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !visibleEpisodes.isEmpty else { return }
                HapticManager.shared.provideFeedback()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedShows.remove(show.feedURL) }
                    else { expandedShows.insert(show.feedURL) }
                }
            }
            .swipeEditDelete(
                onEdit: { activeSheet = .episodePicker(show) },
                onDelete: { removeShowFromFolder(show) }
            )

            if isExpanded {
                ExpandedEpisodeListSection(
                    jumpContextID: "show-\(show.feedURL)",
                    episodes: visibleEpisodes,
                    queueContext: .show(show.persistentModelID),
                    onEdit: { activeSheet = .editEpisode($0) },
                    onDelete: { removeEpisodeFromFolder($0) }
                )
            }
        }
    }

    private func deleteFolder() {
        FavoriteFolderService.removePinsInvolving(folder: folder, context: modelContext)
        modelContext.delete(folder)
        try? modelContext.save()
    }

    @MainActor
    private func removeShowFromFolder(_ show: Show) {
        for f in show.groups { f.shows.removeAll { $0.feedURL == show.feedURL } }
        modelContext.delete(show)
        try? modelContext.save()
        refreshListCache()
    }

    @MainActor
    private func removeEpisodeFromFolder(_ episode: Episode) {
        episode.groups.removeAll { $0.persistentModelID == folder.persistentModelID }
        folder.episodes.removeAll { $0.persistentModelID == episode.persistentModelID }
        try? modelContext.save()
        refreshListCache()
    }

    @MainActor
    private func moveShow(payload: String, to targetFolder: Folder) {
        let parts = payload.components(separatedBy: "\t")
        let feedURL = parts[0]
        let sourceFolderName = parts.count > 1 ? parts[1] : nil

        let descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.feedURL == feedURL })
        guard let show = try? modelContext.fetch(descriptor).first else { return }
        guard targetFolder.name != sourceFolderName else { return }

        if let srcName = sourceFolderName,
           let srcIdx = show.groups.firstIndex(where: { $0.name == srcName }) {
            let src = show.groups[srcIdx]
            show.groups.remove(at: srcIdx)
            src.shows.removeAll { $0.feedURL == feedURL }
        }

        guard !targetFolder.shows.contains(where: { $0.feedURL == feedURL }) else { return }
        targetFolder.shows.append(show)
        show.groups.append(targetFolder)
        try? modelContext.save()
    }
}

// MARK: - SubfolderRowView

struct SubfolderRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LanguageSettings.self) private var lang
    @Environment(\.newEpisodeIndicators) private var newEpisodeIndicators
    let folder: Folder
    @Binding var expandedShows: Set<String>

    @AppStorage("folderOrderOption") private var folderOrderKey = FolderOrderOption.name.rawValue
    @AppStorage("folderSortAscending") private var folderSortAscending = true
    @AppStorage("episodeOrderOption") private var episodeOrderKey = EpisodeOrderOption.date.rawValue
    @AppStorage("episodeSortAscending") private var episodeSortAscending = true
    @AppStorage("hidePlayedEpisodes") private var hidePlayedEpisodes = false

    @State private var activeSheet: GroupSheet? = nil
    @State private var isDragTargeted = false
    @State private var isExpanded = false
    @State private var didRestoreState = false
    @State private var listCache = FolderListCache()
    private let newEpisodeIndicatorColor = Color(red: 0.67, green: 0.9, blue: 0.25)

    private var folderStateID: String {
        "\(folder.displayPath)|\(folder.createdAt.timeIntervalSince1970)"
    }

    private var visibleFolderEpisodes: [Episode] {
        listCache.episodes.filteredForLibraryDisplay(hidePlayed: hidePlayedEpisodes)
    }

    private func visibleShowEpisodes(_ show: Show) -> [Episode] {
        show.sortedEpisodes.filteredForLibraryDisplay(hidePlayed: hidePlayedEpisodes)
    }

    private var hasContents: Bool {
        !listCache.children.isEmpty ||
        !listCache.shows.isEmpty ||
        !listCache.episodes.isEmpty
    }

    private var subfolderContainsInProgressEpisode: Bool {
        folderHasDirectInProgressEpisode(folder)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ThumbnailArtworkView(
                    artworkURLString: folder.representativeArtworkURL,
                    placeholderSystemImage: folder.iconName
                )

                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.textOnCardPrimary)
                if newEpisodeIndicators.folderIDs.contains(folder.persistentModelID) {
                    Circle()
                        .fill(newEpisodeIndicatorColor)
                        .frame(width: 8, height: 8)
                }

                if !FavoriteFolderService.isFavoriteLibrarySection(folder) {
                    Button {
                        HapticManager.shared.provideFeedback()
                        FavoriteFolderService.toggleFavorite(folder: folder, context: modelContext)
                    } label: {
                        Image(systemName: folder.isFavorite ? "star.fill" : "star")
                            .font(.subheadline)
                            .foregroundStyle(
                                folder.isFavorite
                                    ? AnyShapeStyle(.yellow)
                                    : AnyShapeStyle(AppPalette.textOnCardSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 8)

                if hasContents {
                    HStack(spacing: 4) {
                        if subfolderContainsInProgressEpisode {
                            Circle().fill(Color.yellow).frame(width: 8, height: 8)
                        }
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.textOnCardSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isDragTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { payloads, _ in
                payloads.forEach { moveShow(payload: $0, to: folder) }
                return true
            } isTargeted: { isDragTargeted = $0 }
            .folderRowContextMenu(
                folder: folder,
                strings: lang.strings,
                modelContext: modelContext,
                onAddSubfolder: { activeSheet = .addSubfolder },
                onReordered: { refreshListCache() }
            )
            .onTapGesture {
                guard hasContents else { return }
                HapticManager.shared.provideFeedback()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            .swipeEditDelete(
                onEdit: { activeSheet = .editFolder },
                onDelete: { deleteFolder() }
            )

            if isExpanded {
                ForEach(listCache.children) { child in
                    Divider().padding(.leading, 24)
                    SubfolderRowView(folder: child, expandedShows: $expandedShows)
                        .padding(.leading, 8)
                }

                ForEach(listCache.shows) { show in
                    Divider().padding(.leading, 24)
                    nestedShowRow(show: show)
                }

                if !visibleFolderEpisodes.isEmpty {
                    Divider().padding(.leading, 24)
                    ExpandedEpisodeListSection(
                        jumpContextID: "\(folderStateID)-episodes",
                        episodes: visibleFolderEpisodes,
                        queueContext: .folder(folder.persistentModelID),
                        onEdit: { activeSheet = .editEpisode($0) },
                        onDelete: { removeEpisodeFromFolder($0) }
                    )
                }
            }
        }
        .onAppear {
            refreshListCache()
            guard !didRestoreState else { return }
            isExpanded = AppSettings.isFolderExpanded(folderID: folderStateID, defaultValue: false)
            didRestoreState = true
        }
        .onChange(of: folderOrderKey) { _, _ in refreshListCache() }
        .onChange(of: folderSortAscending) { _, _ in refreshListCache() }
        .onChange(of: episodeOrderKey) { _, _ in refreshListCache() }
        .onChange(of: episodeSortAscending) { _, _ in refreshListCache() }
        .onChange(of: folder.shows.count) { _, _ in refreshListCache() }
        .onChange(of: folder.episodes.count) { _, _ in refreshListCache() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryContentDidChange)) { _ in
            refreshListCache()
        }
        .onChange(of: isExpanded) { _, newValue in
            AppSettings.setFolderExpanded(newValue, folderID: folderStateID)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editFolder:
                FolderEditView(folder: folder)
            case .addSubfolder:
                FolderEditView(parentFolder: folder)
            case .episodePicker(let show):
                ShowEpisodePickerView(show: show)
            case .editEpisode(let episode):
                AddEpisodeToGroupSheet(episodes: [episode])
            }
        }
    }

    private func refreshListCache() {
        listCache = FolderListCache.make(for: folder)
    }

    @ViewBuilder
    private func nestedShowRow(show: Show) -> some View {
        let isOpen = expandedShows.contains(show.feedURL)
        let visibleEpisodes = visibleShowEpisodes(show)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    ThumbnailArtworkView(
                        artworkURLString: show.representativeArtworkURL,
                        placeholderSystemImage: "dot.radiowaves.left.and.right"
                    )
                    ShowRowView(
                        show: show,
                        showsNewEpisodeIndicator: newEpisodeIndicators.showIDs.contains(show.persistentModelID)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .draggable("\(show.feedURL)\t\(folder.name)")
                .contextMenu {
                    Button(lang.strings.episodeList, systemImage: "list.bullet") {
                        HapticManager.shared.provideFeedback()
                        activeSheet = .episodePicker(show)
                    }
                    Divider()
                    Button(lang.strings.removeFromFolder, systemImage: "trash", role: .destructive) {
                        HapticManager.shared.provideFeedback()
                        removeShowFromFolder(show)
                    }
                }

                if !visibleEpisodes.isEmpty {
                    let showHasInProgress = show.episodes.contains {
                        $0.playbackPosition > 0 && !$0.isPlayed
                    }
                    HStack(spacing: 4) {
                        if showHasInProgress {
                            Circle().fill(Color.yellow).frame(width: 8, height: 8)
                        }
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.textOnCardSecondary)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !visibleEpisodes.isEmpty else { return }
                HapticManager.shared.provideFeedback()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expandedShows.remove(show.feedURL) }
                    else { expandedShows.insert(show.feedURL) }
                }
            }
            .swipeEditDelete(
                onEdit: { activeSheet = .episodePicker(show) },
                onDelete: { removeShowFromFolder(show) }
            )

            if isOpen {
                ExpandedEpisodeListSection(
                    jumpContextID: "show-\(show.feedURL)",
                    episodes: visibleEpisodes,
                    queueContext: .show(show.persistentModelID),
                    onEdit: { activeSheet = .editEpisode($0) },
                    onDelete: { removeEpisodeFromFolder($0) }
                )
            }
        }
    }

    private func deleteFolder() {
        FavoriteFolderService.removePinsInvolving(folder: folder, context: modelContext)
        modelContext.delete(folder)
        try? modelContext.save()
    }

    @MainActor
    private func removeShowFromFolder(_ show: Show) {
        for f in show.groups { f.shows.removeAll { $0.feedURL == show.feedURL } }
        modelContext.delete(show)
        try? modelContext.save()
        refreshListCache()
    }

    @MainActor
    private func removeEpisodeFromFolder(_ episode: Episode) {
        episode.groups.removeAll { $0.persistentModelID == folder.persistentModelID }
        folder.episodes.removeAll { $0.persistentModelID == episode.persistentModelID }
        try? modelContext.save()
        refreshListCache()
    }

    @MainActor
    private func moveShow(payload: String, to targetFolder: Folder) {
        let parts = payload.components(separatedBy: "\t")
        let feedURL = parts[0]
        let sourceFolderName = parts.count > 1 ? parts[1] : nil

        let descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.feedURL == feedURL })
        guard let show = try? modelContext.fetch(descriptor).first else { return }
        guard targetFolder.name != sourceFolderName else { return }

        if let srcName = sourceFolderName,
           let srcIdx = show.groups.firstIndex(where: { $0.name == srcName }) {
            let src = show.groups[srcIdx]
            show.groups.remove(at: srcIdx)
            src.shows.removeAll { $0.feedURL == feedURL }
        }

        guard !targetFolder.shows.contains(where: { $0.feedURL == feedURL }) else { return }
        targetFolder.shows.append(show)
        show.groups.append(targetFolder)
        try? modelContext.save()
    }
}

// MARK: - フォルダ並び替え（コンテキストメニュー）

private extension View {
    func folderRowContextMenu(
        folder: Folder,
        strings: LocalizedStrings,
        modelContext: ModelContext,
        onAddSubfolder: @escaping () -> Void,
        onReordered: @escaping () -> Void
    ) -> some View {
        contextMenu {
            if FolderReorderService.canReorder(folder) {
                Button {
                    FolderReorderService.move(folder, direction: .up, context: modelContext)
                    HapticManager.shared.provideFeedback()
                    onReordered()
                } label: {
                    Label(strings.moveFolderUp, systemImage: "arrow.up")
                }
                .disabled(!FolderReorderService.canMove(folder, direction: .up, context: modelContext))

                Button {
                    FolderReorderService.move(folder, direction: .down, context: modelContext)
                    HapticManager.shared.provideFeedback()
                    onReordered()
                } label: {
                    Label(strings.moveFolderDown, systemImage: "arrow.down")
                }
                .disabled(!FolderReorderService.canMove(folder, direction: .down, context: modelContext))
            }

            Button {
                HapticManager.shared.provideFeedback()
                onAddSubfolder()
            } label: {
                Label(strings.createSubfolder, systemImage: "folder.badge.plus")
            }
        }
    }
}

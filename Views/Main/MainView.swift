import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore
    @Environment(ShareImportCoordinator.self) private var shareImport
    @Environment(EpisodeListJumpCoordinator.self) private var episodeListJumpCoordinator
    @AppStorage("folderOrderOption") private var folderOrderKey = FolderOrderOption.name.rawValue
    @AppStorage("episodeOrderOption") private var episodeOrderKey = EpisodeOrderOption.date.rawValue
    @AppStorage("folderSortAscending") private var folderSortAscending = true
    @AppStorage("episodeSortAscending") private var episodeSortAscending = true

    private var librarySortAnimationToken: String {
        "\(folderOrderKey)|\(episodeOrderKey)|\(folderSortAscending)|\(episodeSortAscending)"
    }
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    private var rootFolders: [Folder] {
        FolderReorderService.orderedRootFolders(folders)
    }

    @Query(sort: [
        SortDescriptor(\Episode.publishedAt, order: .reverse),
        SortDescriptor(\Episode.title)
    ]) private var allEpisodes: [Episode]
    @Query(filter: #Predicate<Show> { $0.isNewRaw == true })
    private var newShows: [Show]
    @Query(filter: #Predicate<Folder> { $0.isNewRaw == true })
    private var newFolders: [Folder]

    @State private var newEpisodeIndicators = NewEpisodeIndicatorSnapshot.empty

    @State private var isPresentingAddShow = false
    @State private var isPresentingEpisodeSearch = false
    @State private var isPresentingPlayer = false
    @State private var isPresentingCreateFolder = false
    @State private var isPresentingSettings = false
    @State private var isPresentingPlanManagement = false
    @State private var isPresentingHelp = false
    @State private var isPresentingMoreMenu = false
    @State private var moreButtonFrame: CGRect = .zero
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var searchResults: [Episode] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isRefreshingShowMetadata = false
    @State private var refreshResultMessage: String?

    var body: some View {
        let s = lang.strings
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if searchText.isEmpty {
                            folderContent
                        } else {
                            searchContent
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onReceive(NotificationCenter.default.publisher(for: .scrollToEpisode)) { notification in
                    guard let audioURL = notification.userInfo?["audioURL"] as? String else { return }
                    let anchorID = EpisodeScrollAnchor.id(audioURL: audioURL)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        scrollProxy.scrollTo(anchorID, anchor: .center)
                    }
                }
            }
            // `.refreshable` の子タスクはインジケータ終了でキャンセルされ、更新処理ごと取り消されて件数がすべて 0 になる。
            // メニューと同様に完了させるため、DispatchQueue 経由で構造化並行性の親子関係を切ってから Task を起動する。
            .refreshable {
                await refreshShowLibraryAfterPullToRefresh(strings: s)
            }
            .background(AppPalette.scene)
            .osmSceneStatusBar()
            .osmSwipeBackToStartup()
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: s.searchPrompt
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // iOS 26 の共有背景（長円）を外し、背景に直接ボタンを置く。
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        headerButtons(strings: s)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        headerButtons(strings: s)
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddShow) {
                AddShowView()
            }
            .sheet(isPresented: $isPresentingEpisodeSearch) {
                EpisodeSearchView()
            }
            .sheet(isPresented: $isPresentingPlayer) {
                PlayerView()
            }
            .sheet(isPresented: $isPresentingCreateFolder) {
                FolderEditView()
            }
            .sheet(isPresented: $isPresentingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isPresentingPlanManagement) {
                PlanManagementView()
            }
            .sheet(isPresented: $isPresentingHelp) {
                HelpView()
            }
            .sheet(isPresented: shareImportSheetBinding) {
                ShareImportSheet(urls: shareImport.pendingURLs)
            }
            .background {
                ShakeDetectView {
                    audioPlayer.seekBackward(by: AppSettings.shakeRewindSeconds)
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let jumpContext = episodeListJumpCoordinator.activeContext {
                        EpisodeListFloatingJumpBar(
                            topAudioURL: jumpContext.topAudioURL,
                            bottomAudioURL: jumpContext.bottomAudioURL
                        )
                    }
                    if audioPlayer.currentEpisode != nil {
                        MiniPlayerView(onTap: { isPresentingPlayer = true })
                    }
                }
                .padding(.bottom, 8)
            }
            .task(priority: .high) {
                await planStore.listenForTransactionUpdatesForever()
            }
            .task {
                await seedDefaultFoldersIfNeeded()
            }
            .alert(s.refreshResultTitle, isPresented: Binding(
                get: { refreshResultMessage != nil },
                set: { if !$0 { refreshResultMessage = nil } }
            )) {
                Button(s.ok) { refreshResultMessage = nil }
            } message: {
                Text(refreshResultMessage ?? "")
            }
            .environment(\.newEpisodeIndicators, newEpisodeIndicators)
            .onAppear {
                NewEpisodeIndicatorSync.refreshAll(in: modelContext)
                refreshNewEpisodeIndicators()
                shareImport.presentConsumedURLs()
            }
            .onChange(of: isPresentingAddShow) { _, isPresenting in
                if !isPresenting {
                    refreshNewEpisodeIndicators()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryContentDidChange)) { _ in
                refreshNewEpisodeIndicators()
            }
            .onChange(of: newShows.count) { _, _ in refreshNewEpisodeIndicators() }
            .onChange(of: newFolders.count) { _, _ in refreshNewEpisodeIndicators() }
            .onChange(of: searchText) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchTask?.cancel()
                    searchResults = []
                }
            }
            .onSubmit(of: .search) {
                let query = searchText.trimmingCharacters(in: .whitespaces)
                guard !query.isEmpty else { return }
                searchTask?.cancel()
                let snapshot = allEpisodes
                searchTask = Task {
                    let filtered = snapshot.filter {
                        $0.title.localizedCaseInsensitiveContains(query) ||
                        $0.summary.localizedCaseInsensitiveContains(query) ||
                        $0.show.title.localizedCaseInsensitiveContains(query)
                    }
                    guard !Task.isCancelled else { return }
                    searchResults = filtered
                }
            }
            .overlay {
                CloudFilePreparationOverlay()
            }
        }
        // シートではなくツールバーごと覆うので、NavigationStack の外に置く。
        .overlay {
            if isPresentingMoreMenu {
                moreMenuOverlay(strings: s)
                    .transition(.opacity)
            }
        }
    }

    private var shareImportSheetBinding: Binding<Bool> {
        Binding(
            get: { shareImport.isPresentingImport },
            set: { isPresenting in
                if !isPresenting { shareImport.clear() }
            }
        )
    }

    private func refreshNewEpisodeIndicators() {
        let snapshot = NewEpisodeIndicatorSnapshot.build(newShows: newShows, newFolders: newFolders)
        guard snapshot != newEpisodeIndicators else { return }
        newEpisodeIndicators = snapshot
    }

    /// メニューからの更新（構造化タスクにぶら下がらないのでキャンセルされにくい）。
    @MainActor
    private func refreshShowLibrary(strings: LocalizedStrings) async {
        guard !isRefreshingShowMetadata else { return }
        isRefreshingShowMetadata = true
        defer { isRefreshingShowMetadata = false }

        let result = await LibraryImportExportService.refreshAllShows(context: modelContext)
        NewEpisodeIndicatorSync.refreshAll(in: modelContext)
        refreshNewEpisodeIndicators()
        refreshResultMessage = strings.refreshResultMessage(
            shows: result.refreshedShows,
            updated: result.updatedEpisodes,
            added: result.addedEpisodes,
            failed: result.failedShows
        )
    }

    /// Pull-to-refresh 専用。`.refreshable` のキャンセルがそのまま伝わると全取得が無効化され (0,0,0,0)、別経路で実行する。
    private func refreshShowLibraryAfterPullToRefresh(strings: LocalizedStrings) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                Task { @MainActor in
                    await refreshShowLibrary(strings: strings)
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var folderContent: some View {
        let s = lang.strings
        if rootFolders.isEmpty {
            ContentUnavailableView(
                s.noFoldersYet,
                systemImage: "folder",
                description: Text(s.noFoldersDescription)
            )
        } else {
            ForEach(rootFolders) { folder in
                GroupSectionView(folder: folder)
            }
            .animation(.default, value: librarySortAnimationToken)
        }
    }

    /// ヘッダーのボタン。背景に直接、白で置く。
    private func headerButtons(strings s: LocalizedStrings) -> some View {
            HStack(spacing: 10) {
                Button {
                    HapticManager.shared.provideFeedback()
                    audioPlayer.skipToNextEpisode()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(audioPlayer.currentEpisode != nil ? 1 : 0.4))
                        .frame(width: 36, height: 36)
                }
                .disabled(audioPlayer.currentEpisode == nil)
                .accessibilityLabel(s.skipToNextEpisode)
                Button {
                    HapticManager.shared.provideFeedback()
                    audioPlayer.toggleRandomMode()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(audioPlayer.isRandomModeEnabled ? 1 : 0.55))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(audioPlayer.isRandomModeEnabled ? s.randomModeOn : s.randomModeOff)
                LibrarySortToolbarMenu()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    withAnimation(.easeOut(duration: 0.12)) {
                        isPresentingMoreMenu = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(s.menuLabel)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { moreButtonFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in
                                moreButtonFrame = frame
                            }
                    }
                }
            }
    }

    /// […] のアイコンメニュー。ボタンの下に右端を揃えて出し、外側のタップで閉じる。
    private func moreMenuOverlay(strings s: LocalizedStrings) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.26)
                    .contentShape(Rectangle())
                    .onTapGesture { closeMoreMenu() }
                    .accessibilityHidden(true)

                MoreActionsMenu(
                    items: moreMenuItems(strings: s),
                    availableWidth: proxy.size.width - MoreActionsMenu.screenMargin * 2
                )
                .padding(.top, moreButtonFrame.maxY + 6)
                .padding(.trailing, MoreActionsMenu.screenMargin)
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { closeMoreMenu() }
    }

    private func moreMenuItems(strings s: LocalizedStrings) -> [MoreActionsMenu.Item] {
        [
            .init(
                systemImage: "arrow.clockwise",
                title: s.updateShowMetadataShort,
                accessibilityLabel: s.updateShowMetadata,
                isEnabled: !isRefreshingShowMetadata
            ) {
                runMoreMenuAction {
                    Task { @MainActor in
                        await refreshShowLibrary(strings: s)
                    }
                }
            },
            .init(systemImage: "plus", title: s.addShow) {
                runMoreMenuAction { isPresentingAddShow = true }
            },
            .init(systemImage: "folder.badge.plus", title: s.createFolder) {
                runMoreMenuAction { isPresentingCreateFolder = true }
            },
            .init(
                systemImage: "tray.and.arrow.down",
                title: s.addEpisodeToFolderShort,
                accessibilityLabel: s.addEpisodeToFolder
            ) {
                runMoreMenuAction { isPresentingEpisodeSearch = true }
            },
            .init(systemImage: "gearshape", title: s.settings) {
                runMoreMenuAction { isPresentingSettings = true }
            },
            .init(systemImage: "crown", title: s.planManagementMenu) {
                runMoreMenuAction { isPresentingPlanManagement = true }
            },
            .init(systemImage: "questionmark.circle", title: s.help) {
                runMoreMenuAction { isPresentingHelp = true }
            },
        ]
    }

    private func closeMoreMenu() {
        withAnimation(.easeOut(duration: 0.12)) {
            isPresentingMoreMenu = false
        }
    }

    private func runMoreMenuAction(_ action: () -> Void) {
        HapticManager.shared.provideFeedback()
        closeMoreMenu()
        action()
    }

    @ViewBuilder
    private var searchContent: some View {
        let s = lang.strings
        if searchResults.isEmpty {
            VStack(spacing: 16) {
                ContentUnavailableView.search(text: searchText)
                // 0 件のときも、検索をやめて一覧へ戻れるようにする。
                Button(s.searchClear) {
                    searchTask?.cancel()
                    searchText = ""
                    searchResults = []
                    isSearchPresented = false
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("search-clear")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(s.episodeCountLabel(searchResults.count))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.persistentModelID) { idx, episode in
                        searchResultRow(for: episode)
                        if idx < searchResults.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(for episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            EpisodeRowView(episode: episode) {
                audioPlayer.play(episode: episode, context: modelContext)
            }
            Text(episode.show.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !episode.groups.isEmpty {
                folderBadges(for: episode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contextMenu {
            ForEach(folders) { folder in
                Button {
                    toggleFolder(folder, for: episode)
                } label: {
                    let inFolder = episode.groups.contains {
                        $0.persistentModelID == folder.persistentModelID
                    }
                    Label(
                        folder.displayPath,
                        systemImage: inFolder ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func folderBadges(for episode: Episode) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(episode.groups) { folder in
                    Text(folder.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(.top, 2)
    }

    @MainActor
    private func toggleFolder(_ folder: Folder, for episode: Episode) {
        if episode.groups.contains(where: { $0.persistentModelID == folder.persistentModelID }) {
            episode.groups.removeAll { $0.persistentModelID == folder.persistentModelID }
            folder.episodes.removeAll { $0.persistentModelID == episode.persistentModelID }
        } else {
            episode.sortOrder = folder.episodes.count
            episode.groups.append(folder)
            folder.episodes.append(episode)
        }
        try? modelContext.save()
    }

    // MARK: - Seed

    @MainActor
    private func seedDefaultFoldersIfNeeded() async {
        DefaultLibrarySeed.insertDefaultRootFoldersIfEmpty(context: modelContext, strings: lang.strings)
        try? modelContext.save()
    }

}

private struct EpisodeListFloatingJumpBar: View {
    @Environment(LanguageSettings.self) private var lang

    let topAudioURL: String
    let bottomAudioURL: String

    var body: some View {
        HStack(spacing: 20) {
            jumpButton(
                systemImage: "arrow.up.to.line",
                accessibilityLabel: lang.strings.jumpToEpisodeListTop
            ) {
                EpisodeScrollAnchor.postScroll(audioURL: topAudioURL)
            }

            jumpButton(
                systemImage: "arrow.down.to.line",
                accessibilityLabel: lang.strings.jumpToEpisodeListBottom
            ) {
                EpisodeScrollAnchor.postScroll(audioURL: bottomAudioURL)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private func jumpButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.provideFeedback()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 右上の […] から開くアイコン一覧メニュー（osm日日是好日の MoreActionsMenu と同じ見た目）。
/// アイコンだけでは意味が伝わりにくいので、下に小さなラベルを付ける。
private struct MoreActionsMenu: View {
    struct Item: Identifiable {
        let systemImage: String
        let title: String
        var accessibilityLabel: String?
        var isEnabled = true
        let action: () -> Void

        var id: String { systemImage }
    }

    static let screenMargin: CGFloat = 12

    let items: [Item]
    /// 表示できる最大幅。表示倍率「拡大」の狭い端末でも画面内に収める。
    let availableWidth: CGFloat

    private let columnCount = 4
    private let buttonSize: CGFloat = 40
    private let iconSize: CGFloat = 20
    private let iconGap: CGFloat = 6
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 8
    private let maxItemWidth: CGFloat = 72
    /// 10pt のラベル 2 行分。行数が違っても段の高さを揃える。
    private let labelHeight: CGFloat = 26

    private var itemWidth: CGFloat {
        let gaps = iconGap * CGFloat(columnCount - 1) + horizontalPadding * 2
        return min(maxItemWidth, (availableWidth - gaps) / CGFloat(columnCount))
    }

    var body: some View {
        let columns = Array(
            repeating: GridItem(.fixed(itemWidth), spacing: iconGap),
            count: columnCount
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                itemButton(item)
            }
        }
        .fixedSize()
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(AppPalette.cardFill, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
    }

    private func itemButton(_ item: Item) -> some View {
        Button(action: item.action) {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(AppPalette.textOnCardPrimary)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(
                        AppPalette.textOnCardSecondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppPalette.cardBorder, lineWidth: 1)
                    }
                Text(item.title)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.textOnCardSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(width: itemWidth, height: labelHeight, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.4)
        .accessibilityLabel(item.accessibilityLabel ?? item.title)
    }
}

import SwiftUI
import SwiftData

private enum ModelStoreBootstrap {
    /// モデル変更後は既存 SQLite と整合しないことがある。失敗時はストアを削除して一度だけ再作成する（ローカルデータは消える）。
    static func makeSharedContainer() -> ModelContainer {
        let schema = Schema([
            Show.self,
            Episode.self,
            Folder.self,
            FavoriteFolderPin.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [configuration])
        }

        do {
            return try open()
        } catch {
            let ns = error as NSError
            NSLog("SwiftData 初期化失敗（再作成を試みます）: \(error)\nuserInfo: \(ns.userInfo)")
            removeFilesAssociatedWithStore(configuration.url)
            do {
                return try open()
            } catch {
                // ストア削除後も失敗した場合、アプリをクラッシュさせずにインメモリで起動する。
                // データは消えるが「毎回即クラッシュ」のループを防ぐ。
                NSLog("SwiftData をインメモリで起動します（ストア削除後も失敗）: \(String(describing: error))")
                return try! ModelContainer(for: schema, configurations: [
                    ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                ])
            }
        }
    }

    private static func removeFilesAssociatedWithStore(_ storeURL: URL) {
        let fm = FileManager.default
        let paths = [storeURL.path, storeURL.path + "-shm", storeURL.path + "-wal"]
        for path in paths {
            try? fm.removeItem(atPath: path)
        }
        let dir = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        // .skipsHiddenFiles を外す: Core Data が作成する隠しファイル（外部バイナリ格納ディレクトリ等）も削除する
        if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) {
            for url in entries where url.lastPathComponent.hasPrefix(prefix) {
                try? fm.removeItem(at: url)
            }
        }
    }
}

@main
struct osmPodApp: App {
    /// `@State` の遅延より先に `PlanStore` を起動し、`Transaction.updates` の購読を StoreKit が期待するタイミングで開始する。
    init() {
        _ = PlanStore.shared
    }

    let sharedModelContainer: ModelContainer = ModelStoreBootstrap.makeSharedContainer()

    @State private var audioPlayer = AudioPlayerService()
    @State private var episodeDownloadService = EpisodeDownloadService()
    @State private var feedRefreshService = FeedRefreshService()
    @State private var languageSettings = LanguageSettings()
    @State private var planStore = PlanStore.shared
    @State private var shareImport = ShareImportCoordinator()
    @State private var episodeListJumpCoordinator = EpisodeListJumpCoordinator()
    @State private var iCloudSyncManager = ICloudSyncManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoRefreshTask: Task<Void, Never>?
    @AppStorage(ThirdPartyDataConsent.storageKey) private var searchConsentDecision = 0

    var body: some Scene {
        WindowGroup {
            MainView()
                .background(AppPalette.scene.ignoresSafeArea())
                .environment(audioPlayer)
                .environment(audioPlayer.playbackChrome)
                .environment(episodeDownloadService)
                .environment(languageSettings)
                .environment(planStore)
                .environment(shareImport)
                .environment(episodeListJumpCoordinator)
                .tint(AppPalette.accentColor)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    shareImport.handleIncomingURL(url)
                }
                .fullScreenCover(
                    isPresented: Binding(
                        get: { abs(searchConsentDecision) != ThirdPartyDataConsent.currentVersion },
                        set: { _ in }
                    )
                ) {
                    NavigationStack {
                        PrivacyView(requiresDecision: true)
                    }
                    .environment(languageSettings)
                    .preferredColorScheme(.light)
                    .tint(AppPalette.accentColor)
                }
                .task {
                    await planStore.listenForTransactionUpdatesForever()
                }
                .task {
                    // 終了前に再生していたエピソードを一時停止状態で復元し、MiniPlayer に表示する。
                    audioPlayer.restoreLastEpisodeIfNeeded(context: sharedModelContainer.mainContext)
                    await planStore.syncPlanWithStore()
                    await feedRefreshService.refreshIfNeeded(context: sharedModelContainer.mainContext, minimumInterval: 0)
                    NewEpisodeIndicatorSync.refreshAll(in: sharedModelContainer.mainContext)
                    iCloudSyncManager.startObserving(context: sharedModelContainer.mainContext)
                    startAutoRefreshLoopIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                audioPlayer.notifyAppBecameActiveForRecovery()
                Task { @MainActor in
                    await planStore.syncPlanWithStore()
                    await feedRefreshService.refreshIfNeeded(context: sharedModelContainer.mainContext)
                    NewEpisodeIndicatorSync.refreshAll(in: sharedModelContainer.mainContext)
                    await iCloudSyncManager.syncOnForeground(context: sharedModelContainer.mainContext)
                }
                startAutoRefreshLoopIfNeeded()
            } else if scenePhase == .background {
                Task { @MainActor in
                    await iCloudSyncManager.syncToCloud(context: sharedModelContainer.mainContext)
                }
                autoRefreshTask?.cancel()
                autoRefreshTask = nil
            } else {
                autoRefreshTask?.cancel()
                autoRefreshTask = nil
            }
        }
    }

    @MainActor
    private func startAutoRefreshLoopIfNeeded() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled else { break }
                await feedRefreshService.refreshIfNeeded(
                    context: sharedModelContainer.mainContext,
                    minimumInterval: 600
                )
            }
        }
    }
}

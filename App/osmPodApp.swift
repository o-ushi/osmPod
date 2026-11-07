import UIKit
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
            PodStartupGate { MainView() }
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
                    OsmStartupLink.shared.opened = true
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

// MARK: - スタートアップ・使い方画面（osm日日是好日と同じ構成）

/// スタートアップ → 使い方 → 本体の順に見せる。本体は下で動かしたまま上に重ねるので、
/// 表示中に届いた URL などの処理は失われない。
struct OsmStartupGate<Content: View, Startup: View, Usage: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let startup: (@escaping (Bool) -> Void) -> Startup
    @ViewBuilder let usage: (@escaping (Bool) -> Void) -> Usage

    @State private var link = OsmStartupLink.shared
    @State private var phase: OsmStartupPhase =
        OsmStartupSettings.showStartup && !OsmStartupLink.shared.opened ? .startup : .done

    var body: some View {
        ZStack {
            content()
                .accessibilityHidden(phase != .done)
            switch phase {
            case .startup:
                startup { dontShowAgain in
                    // チェック ON だと使い方も OFF になるので、その前の値で今回の着地を決める。
                    let showUsageNow = OsmStartupSettings.showUsage
                    if dontShowAgain { OsmStartupSettings.setShowStartup(false) }
                    phase = showUsageNow ? .usage : .done
                }
            case .usage:
                usage { dontShowAgain in
                    if dontShowAgain { OsmStartupSettings.showUsage = false }
                    phase = .done
                }
            case .done:
                EmptyView()
            }
        }
        // 他のアプリや共有から URL で呼ばれたら、設定は変えず、この起動では案内を閉じる。
        .onChange(of: link.opened) { _, opened in
            if opened { phase = .done }
        }
    }
}

enum OsmStartupPhase { case startup, usage, done }

/// アプリの URL 受け口から立てる。立っていればスタートアップと使い方を出さない。
@MainActor
@Observable
final class OsmStartupLink {
    static let shared = OsmStartupLink()
    var opened = false
}

enum OsmStartupSettings {
    static let showStartupKey = "showStartupScreen"
    static let showUsageKey = "showUsageScreen"

    static var showStartup: Bool {
        UserDefaults.standard.object(forKey: showStartupKey) as? Bool ?? true
    }

    static var showUsage: Bool {
        get { UserDefaults.standard.object(forKey: showUsageKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showUsageKey) }
    }

    /// OFF にするときは使い方画面も一緒に OFF にする。
    static func setShowStartup(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: showStartupKey)
        if !value { showUsage = false }
    }
}

struct OsmStartupColors {
    var background = Color(red: 0x3D / 255, green: 0x59 / 255, blue: 0x93 / 255)
    var foreground = Color.white
    var secondary = Color.white.opacity(0.75)
    var accent = Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0xFF / 255)
}

/// 画面下に固定する「次回から表示しない」と確定ボタン。
struct OsmStartupBottomBar: View {
    let colors: OsmStartupColors
    let dontShowAgainLabel: String
    let label: String
    @Binding var dontShowAgain: Bool
    let onPressed: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button {
                dontShowAgain.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                        .font(.title3)
                    Text(dontShowAgainLabel)
                        .font(.subheadline)
                }
                .foregroundStyle(colors.foreground)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(dontShowAgain ? .isSelected : [])

            Button(action: onPressed) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(colors.background)
    }
}

/// アイコン・アプリ名・説明を中央に、右上に言語の旗、下端にボタンを置く画面。
struct OsmStartupView<Language: View>: View {
    var colors = OsmStartupColors()
    let icon: Image
    let appName: String
    let description: String
    let startLabel: String
    let dontShowAgainLabel: String
    @ViewBuilder let languageMenu: () -> Language
    let onContinue: (Bool) -> Void

    @State private var dontShowAgain = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    Text(appName)
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.top, 28)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(colors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                languageMenu()
                    .padding(8)
            }
            .padding(.trailing, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OsmStartupBottomBar(
                colors: colors,
                dontShowAgainLabel: dontShowAgainLabel,
                label: startLabel,
                dontShowAgain: $dontShowAgain
            ) {
                onContinue(dontShowAgain)
            }
        }
        .background(colors.background.ignoresSafeArea())
    }
}

/// スタートアップの後に出す、外部 AI の使い方の画面。下端にボタンを固定する。
struct OsmUsageView<Body: View>: View {
    var colors = OsmStartupColors()
    let title: String
    let doneLabel: String
    let dontShowAgainLabel: String
    @ViewBuilder let content: () -> Body
    let onContinue: (Bool) -> Void

    @State private var dontShowAgain = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(colors.foreground)
                    .frame(maxWidth: .infinity)
                content()
                    .foregroundStyle(colors.foreground)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OsmStartupBottomBar(
                colors: colors,
                dontShowAgainLabel: dontShowAgainLabel,
                label: doneLabel,
                dontShowAgain: $dontShowAgain
            ) {
                onContinue(dontShowAgain)
            }
        }
        .background(colors.background.ignoresSafeArea())
    }
}

/// osmPod のスタートアップと使い方を付けたルート。
struct PodStartupGate<Content: View>: View {
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore
    @ViewBuilder let content: () -> Content

    var body: some View {
        let s = lang.strings
        OsmStartupGate(content: content) { finish in
            OsmStartupView(
                icon: Image(planStore.isFree ? "AppImageFree" : "AppImage"),
                appName: "osmPod",
                description: s.helpIntro,
                startLabel: s.startupStart,
                dontShowAgainLabel: s.startupDontShowAgain,
                languageMenu: { languageMenu },
                onContinue: finish
            )
        } usage: { finish in
            OsmUsageView(
                title: s.usageTitle,
                doneLabel: s.usageGoHome,
                dontShowAgainLabel: s.startupDontShowAgain,
                content: {
                    Text(s.helpTAiTitle)
                        .font(.headline)
                    Text(s.usageCopyBody)
                        .font(.subheadline)
                    Image("chrome_ai_copy_button")
                        .resizable()
                        .scaledToFit()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel(s.usageCopyImageLabel)
                },
                onContinue: finish
            )
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button("\(language.flag) \(language.displayName)") {
                    lang.language = language
                }
            }
        } label: {
            Text(lang.language.flag)
                .font(.title)
        }
    }
}

/// osm日日是好日と同じく、ヘッダーのボタンを背景に直接置く（iOS 26 のガラスの地を出さない）。
extension ToolbarContent {
    @ToolbarContentBuilder
    func osmPlainBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

// MARK: - 下スワイプ・左端スワイプで閉じる（osm日日是好日と同じ）

extension View {
    /// プッシュした画面に付ける。戻るボタンは出さず、いちばん上からの下スワイプと
    /// 左端からの右スワイプで前の画面へ戻る。シートの中でも、シートごと閉じず 1 画面だけ戻る。
    func osmSwipeToClose() -> some View {
        navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(true)
            .background(OsmSwipeToCloseInstaller().frame(width: 0, height: 0))
    }
}

private struct OsmSwipeToCloseInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> OsmSwipeToCloseController { OsmSwipeToCloseController() }
    func updateUIViewController(_ controller: OsmSwipeToCloseController, context: Context) {}
}

final class OsmSwipeToCloseController: UIViewController, UIGestureRecognizerDelegate {
    private static let closeDistance: CGFloat = 96
    private static let closeVelocity: CGFloat = 500

    private weak var nav: UINavigationController?
    private var pan: UIPanGestureRecognizer?
    private weak var previousPopDelegate: UIGestureRecognizerDelegate?
    private var startedAtTop = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let nav = navigationController, pan == nil else { return }
        self.nav = nav
        // 戻るボタンを隠すと無効になる、左端からの右スワイプを生かす。
        previousPopDelegate = nav.interactivePopGestureRecognizer?.delegate
        nav.interactivePopGestureRecognizer?.isEnabled = true
        nav.interactivePopGestureRecognizer?.delegate = self
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        nav.view.addGestureRecognizer(pan)
        self.pan = pan
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let pan { nav?.view.removeGestureRecognizer(pan) }
        pan = nil
        nav?.interactivePopGestureRecognizer?.delegate = previousPopDelegate
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        (nav?.viewControllers.count ?? 0) > 1
    }

    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        recognizer === pan
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let view = nav?.view else { return }
        switch pan.state {
        case .began:
            startedAtTop = Self.isAtTop(view.hitTest(pan.location(in: view), with: nil))
        case .ended:
            let move = pan.translation(in: view)
            let speed = pan.velocity(in: view)
            guard startedAtTop, move.y > abs(move.x) * 1.25, speed.y > 0 else { return }
            guard move.y >= Self.closeDistance || speed.y >= Self.closeVelocity else { return }
            nav?.popViewController(animated: true)
        default:
            break
        }
    }

    /// 触れた場所の縦スクロールがいちばん上か。地図の上では閉じない。
    private static func isAtTop(_ hit: UIView?) -> Bool {
        var view = hit
        while let current = view {
            if String(describing: type(of: current)).contains("MKMapView") { return false }
            if let scroll = current as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                return scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1
            }
            view = current.superview
        }
        return true
    }
}

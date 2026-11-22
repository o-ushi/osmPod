@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
import Network
import SwiftData
import UIKit
import os.log

private let bgLog = Logger(subsystem: "com.osamushikubo.osmPod", category: "BGAudio")

/// ポッドキャスト再生中か（UI フィードバック音が AVPlayer とセッションを奪わないようにする）。
@MainActor
enum PodcastPlaybackActivity {
    static var isActive = false
}

/// ライブラリ行向けの再生表示。`currentTime` より低頻度で更新し、スクロール中の再描画を抑える。
@MainActor
@Observable
final class PlaybackChromeState {
    fileprivate(set) var nowPlayingEpisodeID: PersistentIdentifier?
    fileprivate(set) var isPlaying = false
    fileprivate(set) var liveDisplayTime: TimeInterval = 0
}

/// 読み込みが止まったまま再生できず、自動で止めたときの知らせ。
enum PlaybackNotice: Equatable {
    /// 何度読み込み直しても音声が届かなかった。
    case stalledGaveUp
    /// 配信元からの転送が再生に必要な速さを大きく下回り、待っても流れなかった。
    case sourceTooSlow
}

enum PlaybackQueueContext: Equatable {
    case none
    case folder(PersistentIdentifier)
    case show(PersistentIdentifier)
}

@MainActor
@Observable
final class AudioPlayerService {
    /// `NowPlayingSyncCoordinator` から参照するため internal（`private` にすると別ファイルから見えない）。
    @ObservationIgnored var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    /// `nonisolated deinit` から解除できるようにする（トークン自体はスレッド拘束される前提で単独利用）。
    @ObservationIgnored nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var appWillResignActiveObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var appDidEnterBackgroundObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var appWillEnterForegroundObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var memoryWarningObserver: NSObjectProtocol?
    @ObservationIgnored private var stalledObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var timeControlObserver: NSKeyValueObservation?
    @ObservationIgnored nonisolated(unsafe) private var rateObserver: NSKeyValueObservation?
    @ObservationIgnored private var lastStalledReloadUptime: TimeInterval = 0
    /// `.waitingToPlayAtSpecifiedRate` に張り付いたまま戻らない状態を検知するウォッチドッグ。
    /// isPlaying=true のまま rate=1 を書き続けると実際には音が止まっているのに再生中扱いが続くため、
    /// 一定時間 waiting が続いたら stall 扱いでリロードする。
    @ObservationIgnored private var waitingStallWatchdogTask: Task<Void, Never>?
    /// AVPlayer.seek が完了するまでタイマーによる currentTime 上書きを抑制するフラグ。
    @ObservationIgnored private var isSeeking = false
    /// seek のたびに増やす。古い seek の完了で、新しい seek の `isSeeking` を下ろさないようにする。
    @ObservationIgnored private var seekGeneration = 0
    /// 直近の seek の目標位置。AVPlayer の実時刻がここに近づくまで、周期サンプルで時刻を上書きしない
    /// （seek 前に採取されたサンプルが完了後に届き、表示が元の時刻へ跳ね返るのを防ぐ）。
    @ObservationIgnored private var pendingSeekTarget: TimeInterval?
    /// 直近の seek が完了した時刻。目標に届かないまま待ち続けないための逃げ道。
    @ObservationIgnored private var seekCompletedUptime: TimeInterval = 0
    /// 実時刻がこの範囲に入ったら、seek の目標に着いたとみなす。
    private static let seekArrivalTolerance: TimeInterval = 3
    /// seek 完了からこの時間たっても目標付近にならなければ、実時刻を受け入れる。
    private static let seekArrivalTimeout: TimeInterval = 3
    /// `play()` / `setActive` の連打はオーディオグラフの切り替えノイズになるため間引く。
    @ObservationIgnored private var lastPlaybackRecoveryUptime: TimeInterval = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var modelContext: ModelContext?
    /// `setCategory` の繰り返しは SessionCore の「Failed to set properties」につながるため、一度だけ適用する。
    @ObservationIgnored private var didApplyPlaybackCategory = false
    /// こちらが `setActive(true)` したままかどうか。停止のたびに `setActive(false)` を連打するとクリックノイズになる。
    @ObservationIgnored private var playbackAudioSessionIsActive = false
    /// `willEnterForeground` と SwiftUI の `scenePhase` が短時間に二度続くのを抑止する。
    @ObservationIgnored private var lastForegroundRecoveryUptime: TimeInterval = 0
    /// バックグラウンド中は保存間隔を延長して SwiftData WAL 蓄積を抑制するためのフラグ。
    /// `NowPlayingSyncCoordinator` から参照するため internal。
    @ObservationIgnored var isInBackground = false
    /// バックグラウンド中の再生位置（SwiftData / @Observable を触らず jetsam を避ける）。
    /// `NowPlayingSyncCoordinator` から参照するため internal。
    @ObservationIgnored var inMemoryPlaybackPosition: TimeInterval = 0
    @ObservationIgnored private var backgroundNowPlayingTask: Task<Void, Never>?
    /// item.status=.failed やバッファリング詰まりでネットワーク復帰待ちの間、実際には音が
    /// 止まっているのに isPlaying=true のままになる状態。isPlaying 自体は「ユーザーの再生意図」
    /// として復帰ロジック（startNetworkRecoveryMonitor 等）にそのまま使うため変更せず、
    /// NowPlayingInfo の rate/playbackState 補正だけに使う。
    /// `NowPlayingSyncCoordinator` から参照するため internal。
    @ObservationIgnored var isNetworkStalled = false {
        didSet { refreshWaitingIndicator() }
    }
    /// 再生しようとしているのに、通信が来なくて音が出ていない（画面に「接続待ち」を出す）。
    /// 再生開始やシーク直後の短い読み込みでちらつかないよう、待ちが 3 秒続いたら立てる。
    private(set) var isWaitingForConnection = false
    @ObservationIgnored private var waitingIndicatorTask: Task<Void, Never>?
    /// 音が届かず読み込み直した回数。実際に流れ始めたら 0 に戻す。
    @ObservationIgnored private var stallRetryCount = 0
    /// この回数読み込み直しても流れなければ、止めて知らせる。
    private static let maxStallRetries = 4
    /// 待ちを見張る時間。読み込み直すたびに延ばす（同じ間隔で連打しない）。
    private static let stallRetryTimeouts: [TimeInterval] = [15, 20, 30, 45, 60]
    /// 配信元が遅いとき、音が出ないままこれだけ待ったら止める。
    private static let slowSourceGiveUpAfter: TimeInterval = 180
    /// 配信元が遅いときの見張りの間隔（読み込み直さず、速さだけ測り直す）。
    private static let slowSourceRecheckInterval: TimeInterval = 30
    /// 配信元からの転送が、再生に必要な速さを大きく下回っている。
    /// このときは読み込み直しても速くならない（読み込み済みの分を捨てるぶん不利）ので、待ち続ける。
    private(set) var isSourceSlow = false
    /// 配信元が遅いと分かってから、音が出ないまま待っている起点。
    @ObservationIgnored private var slowWaitStartedUptime: TimeInterval?
    /// 再生に必要な速さ（bit/s）。音声トラックの見積もりから読む。
    /// MP3 では見積もりが 0（不明）のことが多いので、そのときは控えめに 64kbps とみなす
    /// （明らかに遅い配信元だけを「遅い」と判断するため）。
    @ObservationIgnored private var requiredBitrate: Double?
    private static let fallbackRequiredBitrate: Double = 64_000
    /// 今の AVPlayerItem を作った時刻。届いたバイト数から速さを割り出すときの起点。
    @ObservationIgnored private var currentItemStartedUptime: TimeInterval = 0
    /// 読み込めずに自動で止めたときの知らせ。次に再生を始めたら消す。
    private(set) var playbackNotice: PlaybackNotice?
    /// 割り込み開始時点で再生していたか（手動停止後の誤った自動再開を防ぐ）。
    /// `NowPlayingSyncCoordinator` から参照するため internal。
    @ObservationIgnored nonisolated(unsafe) var wasPlayingAtInterruption = false
    /// 再生完了直後に scene/lifecycle 復帰で誤って再開しないためのフラグ。
    /// `NowPlayingSyncCoordinator` から参照するため internal。
    @ObservationIgnored var didReachPlaybackEnd = false
    /// Security-scoped folder access kept alive while a localfolder:// episode is playing.
    @ObservationIgnored private var activeFolderAccess: (url: URL, accessed: Bool)?
    @ObservationIgnored private var lastChromeLiveTimePublishSecond: Int = -1
    /// エピソード切り替えの瞬間に古い再生セッションの非同期コールバック（タイマー Tick・duration 読み込み）が
    /// 紛れ込み、新しいエピソードの currentTime/duration を上書きしてしまう競合を防ぐための世代カウンタ。
    @ObservationIgnored private var playbackGeneration = 0
    /// AVPlayerItem.status の KVO 監視（failed 検知用）。
    @ObservationIgnored nonisolated(unsafe) private var itemStatusObserver: NSKeyValueObservation?
    /// 圏外で item が failed になったとき、ネットワーク復帰を監視して自動リロードするモニター。
    @ObservationIgnored nonisolated(unsafe) private var networkRecoveryMonitor: NWPathMonitor?
    /// ネットワーク復帰リロードの連打を防ぐクールダウン用タイムスタンプ。
    @ObservationIgnored private var lastNetworkRecoveryUptime: TimeInterval = 0
    /// reloadCurrentStreamPreservingState の先頭で確定した resumeAt（replaceCurrentItem 前に記録）。
    /// attachItemStatusObserver が item 失敗をキャプチャするとき、currentTime が
    /// replaceCurrentItem 後に 0 で上書きされていても正しい位置を使えるようにする。
    /// 値が 0 未満なら「リロード経由でない失敗」として currentTime を使う。
    @ObservationIgnored private var pendingReloadResumeAt: TimeInterval = -1

    /// 一覧のハイライト用。`AudioPlayerService.currentTime` とは更新頻度を分離する。
    let playbackChrome = PlaybackChromeState()
    /// Dropbox 等クラウドファイルの再生準備 UI 用。
    let cloudFilePreparation = CloudFilePreparationState()
    /// Now Playing（CC / ロック画面）同期の専用コーディネータ。`init` 内で `owner` を自分自身に設定する。
    @ObservationIgnored private let nowPlayingSync = NowPlayingSyncCoordinator()

    private(set) var currentEpisode: Episode?
    private(set) var isPlaying = false
    private(set) var isRepeatEnabled = false
    private(set) var isRandomModeEnabled = AppSettings.randomModeEnabled
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var queueContext: PlaybackQueueContext = .none

    init() {
        nowPlayingSync.owner = self
        configureAudioSessionCategory()
        setupSessionObservers()
        setupApplicationLifecycleObservers()
        // MPNowPlayingSession は AVPlayer が最低 1 つ無いと生成できないため、リモートコマンドの
        // 登録は最初の AVPlayer ができたタイミング（nowPlayingSync.attachPlayer 内）まで遅延する。
    }

    /// アプリ起動直後にカテゴリだけ確定させる。`setActive` は実際の再生直前に呼ぶ。
    private func configureAudioSessionCategory() {
        // UIBackgroundModes の確認（array で "audio" が含まれていないとバックグラウンド再生が機能しない）
        let rawModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes")
        if let modes = rawModes as? [String] {
            if modes.contains("audio") {
                bgLog.info("✅ UIBackgroundModes: \(modes)")
            } else {
                bgLog.error("❌ UIBackgroundModes に 'audio' が含まれていません: \(modes)")
            }
        } else if let str = rawModes as? String {
            bgLog.error("❌ UIBackgroundModes が String 型です ('\(str)'): Signing & Capabilities で設定し直してください")
        } else {
            bgLog.error("❌ UIBackgroundModes が Info.plist に存在しません: Xcode → Signing & Capabilities → Background Modes → Audio にチェックを入れてください")
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            didApplyPlaybackCategory = true
            bgLog.info("✅ session category set at launch")
        } catch {
            bgLog.error("❌ session category failed at launch: \(error)")
        }
    }

    /// フォアグラウンド復帰時（SwiftUI の `scenePhase == .active` など）。`willEnterForeground` と二重に呼ばれても間引く。
    func notifyAppBecameActiveForRecovery() {
        handleReturnedToForegroundDebounced()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let appWillResignActiveObserver {
            NotificationCenter.default.removeObserver(appWillResignActiveObserver)
        }
        if let appDidEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(appDidEnterBackgroundObserver)
        }
        if let appWillEnterForegroundObserver {
            NotificationCenter.default.removeObserver(appWillEnterForegroundObserver)
        }
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func play(
        episode: Episode,
        context: ModelContext,
        queueContext: PlaybackQueueContext = .none
    ) {
        modelContext = context

        if currentEpisode?.persistentModelID == episode.persistentModelID {
            if player == nil {
                beginPlayback(episode: episode, context: context, queueContext: queueContext)
            } else {
                togglePlayPause()
            }
            return
        }

        beginPlayback(episode: episode, context: context, queueContext: queueContext)
    }

    private func beginPlayback(
        episode: Episode,
        context: ModelContext,
        queueContext: PlaybackQueueContext
    ) {
        modelContext = context

        // アプリ強制終了後も再開できるよう、再生開始時点の audioURL を記録する。
        AppSettings.lastPlayingEpisodeAudioURL = episode.audioURL
        teardownPlayer()
        playbackGeneration += 1
        let generation = playbackGeneration
        self.queueContext = queueContext
        currentEpisode = episode
        currentTime = episode.playbackPosition
        // 前のエピソードの末尾の位置を、バックグラウンドの読み込み直しで新しいエピソードに使わない。
        inMemoryPlaybackPosition = episode.playbackPosition
        duration = episode.totalDuration
        didReachPlaybackEnd = false
        resetStallTracking()
        requiredBitrate = nil
        playbackNotice = nil
        episode.clearNewIndicator()
        if !isInBackground { try? context.save() }

        guard let url = resolvePlaybackURL(for: episode) else { return }

        let isBookmarkedLocal = episode.audioURL.hasPrefix("localfile://")
            || episode.audioURL.hasPrefix("localfolder://")

        nowPlayingSync.refreshNowPlayingArtwork(for: episode)

        if isBookmarkedLocal {
            Task { [weak self] in
                await self?.prepareBookmarkedFileAndStartPlayback(
                    url: url,
                    episode: episode,
                    generation: generation
                )
            }
        } else {
            startPlayback(
                url: url,
                episode: episode,
                isBookmarkedLocal: false,
                generation: generation
            )
        }
    }

    func toggleRepeat() {
        isRepeatEnabled.toggle()
    }

    func toggleRandomMode() {
        isRandomModeEnabled.toggle()
        AppSettings.randomModeEnabled = isRandomModeEnabled
        // ランダムモードをオフにした瞬間、現在のエピソードのショーをコンテキストに設定する。
        // これにより「このエピソードの続きをシーケンシャルに再生」という意図が実現される。
        if !isRandomModeEnabled, let episode = currentEpisode {
            queueContext = .show(episode.show.persistentModelID)
        }
    }

    func togglePlayPause() {
        if player == nil, let episode = currentEpisode, let context = modelContext {
            beginPlayback(episode: episode, context: context, queueContext: queueContext)
            return
        }
        if isPlaying {
            pausePlayback(trigger: "button")
        } else {
            resumePlayback(trigger: "button")
        }
    }

    /// `NowPlayingSyncCoordinator` のリモートコマンドハンドラから呼ぶため internal。
    func resumePlayback(trigger: String) {
        if player == nil, let episode = currentEpisode, let context = modelContext {
            beginPlayback(episode: episode, context: context, queueContext: queueContext)
            return
        }
        guard let player, !isPlaying else { return }
        nowPlayingSync.logNowPlayingEvent("resumePlayback", trigger: trigger, extra: "phase=enter")
        resetStallTracking()
        playbackNotice = nil
        preparePlaybackAudioSession()
        currentEpisode?.clearNewIndicator()
        if didReachPlaybackEnd {
            didReachPlaybackEnd = false
            currentTime = 0
            currentEpisode?.playbackPosition = 0
            currentEpisode?.isPlayed = false
            let t = CMTime(seconds: 0, preferredTimescale: 600)
            player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        // failed な AVPlayerItem は回復不能（圏外中にリロードされた item がこの状態になる）。
        // player.play() を呼んでも何も起きないため、item を再生成してから再生を開始する。
        // currentTime が壊れている可能性があるため episode.playbackPosition をフォールバックとして使う。
        if let item = player.currentItem, item.status == .failed, let episode = currentEpisode {
            let safePosition = max(currentTime, episode.playbackPosition)
            bgLog.info("▶️ resumePlayback: item.status=.failed at \(safePosition)s → reloading stream")
            isPlaying = true
            lastChromeLiveTimePublishSecond = -1
            syncPlaybackChrome(liveTime: currentTime)
            syncPlaybackActivityFlag()
            if isInBackground { startBackgroundPositionTracking() } else { startPeriodicSave() }
            nowPlayingSync.applyNowPlayingInfo()
            nowPlayingSync.syncRemoteCommandsAvailability()
            nowPlayingSync.scheduleNowPlayingReassert()
            reloadCurrentStreamPreservingState(episode: episode, forcedResumeAt: safePosition)
            nowPlayingSync.logNowPlayingEvent("resumePlayback", trigger: trigger, extra: "phase=exit reloadedFailedItem=true")
            return
        }
        playCurrentItem()
        isPlaying = true
        lastChromeLiveTimePublishSecond = -1
        syncPlaybackChrome(liveTime: currentTime)
        syncPlaybackActivityFlag()
        if isInBackground {
            startBackgroundPositionTracking()
        } else {
            startPeriodicSave()
        }
        nowPlayingSync.applyNowPlayingInfo()
        nowPlayingSync.syncRemoteCommandsAvailability()
        nowPlayingSync.scheduleNowPlayingReassert()
        nowPlayingSync.logNowPlayingEvent("resumePlayback", trigger: trigger, extra: "phase=exit")
    }

    /// `NowPlayingSyncCoordinator` のリモートコマンドハンドラから呼ぶため internal。
    func pausePlayback(trigger: String) {
        guard let player, isPlaying else { return }
        nowPlayingSync.logNowPlayingEvent("pausePlayback", trigger: trigger, extra: "phase=enter")
        stopNetworkRecoveryMonitor()
        let pausedAt = player.currentTime().seconds
        isPlaying = false
        isNetworkStalled = false
        wasPlayingAtInterruption = false  // 手動停止なので割り込み終了後の自動再開を抑制する
        player.pause()
        // failed item は player.currentTime() が 0 などの不正値を返すため更新しない。
        // isSeeking 中も seek 先へのジャンプ前の値で上書きしない。
        let itemIsHealthy = player.currentItem?.status != .failed
        if itemIsHealthy, !isSeeking, pausedAt.isFinite, pausedAt >= 0 {
            if isInBackground {
                inMemoryPlaybackPosition = pausedAt
            } else {
                currentTime = pausedAt
            }
        }
        // 手動一時停止はこの後いつフォアグラウンドに戻るか分からないチェックポイントなので、
        // バックグラウンド中でも即座にディスクへ書く（そうしないと復帰前にプロセスが
        // 回収された場合に位置が失われ、再開時に最初に戻ってしまう）。
        persistPosition(force: true)
        syncPlaybackChrome(liveTime: nil)
        syncPlaybackActivityFlag()
        if isInBackground {
            backgroundNowPlayingTask?.cancel()
            backgroundNowPlayingTask = nil
        } else {
            saveTask?.cancel()
            saveTask = nil
        }
        let elapsed = (pausedAt.isFinite && pausedAt >= 0) ? pausedAt : nil
        publishPausedNowPlaying(
            elapsed: elapsed,
            notifyOthersOnDeactivation: true,
            releaseInBackground: true
        )
        nowPlayingSync.logNowPlayingEvent("pausePlayback", trigger: trigger, extra: "phase=exit")
    }

    func seekForward(by seconds: Double = 15) {
        let base = isInBackground ? inMemoryPlaybackPosition : currentTime
        let target = duration > 0 ? min(base + seconds, duration) : base + seconds
        applySeek(to: target)
    }

    func seekBackward(by seconds: Double = 15) {
        let base = isInBackground ? inMemoryPlaybackPosition : currentTime
        applySeek(to: max(base - seconds, 0))
    }

    func seek(to seconds: TimeInterval) {
        applySeek(to: seconds)
    }

    /// 現在のエピソードを「再生済み」にせず、次のエピソードへ手動で進む。
    /// 自然終了時の `enqueueNextEpisode` と同じ優先順位（ランダム → 同じ番組の隣 → 設定の自動再生）で次を選ぶ。
    func skipToNextEpisode() {
        guard let current = currentEpisode, let context = modelContext else { return }

        if isRandomModeEnabled {
            if let next = randomModeNextEpisode(after: current) {
                play(episode: next, context: context, queueContext: .none)
            }
            return
        }
        if let next = nextEpisodeToAutoPlay(after: current) {
            play(episode: next, context: context, queueContext: .show(current.show.persistentModelID))
            return
        }
        if let next = globalAutoPlayNextEpisode(after: current) {
            play(episode: next, context: context, queueContext: .none)
        }
    }

    // MARK: - Private

    private func resolvePlaybackURL(for episode: Episode) -> URL? {
        if let localPath = episode.downloadedAudioPath,
           FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        if let folderFileURL = resolveLocalFolderURL(for: episode) {
            return folderFileURL
        }
        if let remoteURL = URL(string: episode.audioURL) {
            return remoteURL
        }
        return nil
    }

    private func prepareBookmarkedFileAndStartPlayback(
        url: URL,
        episode: Episode,
        generation: Int
    ) async {
        let needsOverlay = await BookmarkedFilePlaybackPreparer.needsPreparation(at: url)
        if needsOverlay {
            cloudFilePreparation.begin(fileName: url.lastPathComponent)
        }
        defer {
            if needsOverlay {
                cloudFilePreparation.end()
            }
        }

        let prepared = await prepareBookmarkedFileIfNeeded(
            url: url,
            generation: generation,
            resumeAt: max(episode.playbackPosition, currentTime)
        )
        guard prepared, playbackGeneration == generation else { return }

        startPlayback(
            url: url,
            episode: episode,
            isBookmarkedLocal: true,
            generation: generation,
            autoPlay: false
        )
        guard playbackGeneration == generation else { return }

        let ready = await waitForPlayerItemReady(generation: generation)
        if !ready {
            bgLog.error("player item not ready after bookmarked cloud prep")
            isPlaying = false
            syncPlaybackChrome()
            syncPlaybackActivityFlag()
            nowPlayingSync.syncRemoteCommandsAvailability()
            nowPlayingSync.updateNowPlaying()
            startNetworkRecoveryMonitor(resumeAt: max(currentTime, episode.playbackPosition))
        }
    }

    /// AVPlayerItem が readyToPlay になるまで待つ。オーバーレイは呼び出し側が管理する。
    private func waitForPlayerItemReady(generation: Int, timeout: TimeInterval = 60) async -> Bool {
        cloudFilePreparation.setPhase(.startingPlayback)
        cloudFilePreparation.updateProgress(nil)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard playbackGeneration == generation else { return false }

            guard let item = player?.currentItem else {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }

            switch item.status {
            case .readyToPlay:
                playCurrentItem()
                isPlaying = true
                lastChromeLiveTimePublishSecond = -1
                syncPlaybackChrome(liveTime: currentTime)
                syncPlaybackActivityFlag()
                if isInBackground {
                    startBackgroundPositionTracking()
                } else {
                    startPeriodicSave()
                }
                nowPlayingSync.updateNowPlaying()
                nowPlayingSync.syncRemoteCommandsAvailability()
                nowPlayingSync.scheduleNowPlayingReassert()
                return true
            case .failed:
                return false
            case .unknown:
                break
            @unknown default:
                break
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        return player?.currentItem?.status == .readyToPlay
    }

    @discardableResult
    private func prepareBookmarkedFileIfNeeded(
        url: URL,
        generation: Int,
        resumeAt: TimeInterval
    ) async -> Bool {
        do {
            try await BookmarkedFilePlaybackPreparer.ensurePlayable(at: url) { [weak self] progress in
                Task { @MainActor in
                    self?.cloudFilePreparation.updateProgress(progress)
                }
            }
        } catch {
            bgLog.error("cloud file prep failed: \(error.localizedDescription, privacy: .public)")
            guard playbackGeneration == generation else { return false }
            // reload 経由の場合、この時点ではまだ古い player/item が生きている可能性がある。
            // isPlaying だけ false にして実際の音声を止め忘れると「表示は停止・実際は再生中」の
            // 逆desyncになるため、明示的に一時停止させる。
            player?.pause()
            isPlaying = false
            syncPlaybackChrome()
            syncPlaybackActivityFlag()
            nowPlayingSync.syncRemoteCommandsAvailability()
            nowPlayingSync.updateNowPlaying()
            startNetworkRecoveryMonitor(resumeAt: resumeAt)
            return false
        }
        return true
    }

    private func startPlayback(
        url: URL,
        episode: Episode,
        isBookmarkedLocal: Bool,
        generation: Int,
        autoPlay: Bool = true
    ) {
        preparePlaybackAudioSession()

        // localfile:// / localfolder:// エピソードはブックマーク経由のファイルで、
        // Dropbox 等のクラウドストレージの場合は File Provider のデータ取得待ちが必要。
        // url.isFileURL が true でも即時再生モードにすると即座に失敗するため、
        // ストリーミングと同様に automaticallyWaitsToMinimizeStalling を有効にする。
        installPlayer(
            url: url,
            episode: episode,
            isBookmarkedLocal: isBookmarkedLocal,
            generation: generation
        )

        guard autoPlay else {
            isPlaying = false
            player?.defaultRate = 0
            syncPlaybackChrome()
            nowPlayingSync.syncRemoteCommandsAvailability()
            return
        }

        playCurrentItem()
        isPlaying = true
        lastChromeLiveTimePublishSecond = -1
        syncPlaybackChrome(liveTime: currentTime)
        syncPlaybackActivityFlag()
        if isInBackground {
            startBackgroundPositionTracking()
        } else {
            startPeriodicSave()
        }
        nowPlayingSync.updateNowPlaying()
        nowPlayingSync.syncRemoteCommandsAvailability()
        nowPlayingSync.scheduleNowPlayingReassert()
    }

    private func makePlayerItem(url: URL, isLocalFile: Bool) -> AVPlayerItem {
        currentItemStartedUptime = ProcessInfo.processInfo.systemUptime
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        if !isLocalFile {
            // 他アプリで CPU を奪われても切れ欠けしにくいようストリームだけ先読みを厚めにする。
            item.preferredForwardBufferDuration = 45
        }
        return item
    }

    private func syncPlaybackActivityFlag() {
        PodcastPlaybackActivity.isActive = isPlaying && player != nil
    }

    /// セッションの再構成なしで再開を試みる（`setActive` の連打はクリックノイズの原因になりやすい）。
    private func resumePlaybackAfterUnexpectedPause(minimumCooldown: TimeInterval = 2.0) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlaybackRecoveryUptime >= minimumCooldown else { return }
        lastPlaybackRecoveryUptime = now

        guard let player, isPlaying, !didReachPlaybackEnd else { return }

        if let item = player.currentItem,
           item.isPlaybackBufferEmpty,
           !item.isPlaybackLikelyToKeepUp {
            bgLog.info("resume deferred: playback buffer not ready")
            return
        }

        bgLog.info("▶️ resume play() without session reconfigure")
        playCurrentItem()
        if isInBackground {
            startBackgroundPositionTracking()
        } else {
            startPeriodicSave()
        }
        nowPlayingSync.updateNowPlaying()
        nowPlayingSync.logNowPlayingEvent("resumePlaybackAfterUnexpectedPause", trigger: "observer")
    }

    private func syncPlaybackChrome(liveTime: TimeInterval? = nil) {
        playbackChrome.nowPlayingEpisodeID = currentEpisode?.persistentModelID
        playbackChrome.isPlaying = isPlaying
        if let liveTime {
            playbackChrome.liveDisplayTime = liveTime
        } else if currentEpisode == nil {
            playbackChrome.liveDisplayTime = 0
        }
    }

    private func attachPeriodicTimeObserver(generation: Int) {
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 直前のエピソードのタイマー Tick が、再生切り替え後にずれて届くのを防ぐ。
                guard self.playbackGeneration == generation else { return }
                guard self.isPlaying else { return }
                // replaceCurrentItem 直後や failed item は時刻 0 などの不正値を返すためスキップ。
                guard let player = self.player, player.currentItem?.status != .failed else { return }
                // `time` はこの Task より前に採取された値で、間に seek が終わっていると古い位置になる。
                // MainActor に乗った今の実時刻を読む。
                let live = player.currentTime().seconds
                let secs = live.isFinite ? live : time.seconds
                guard secs.isFinite, secs >= 0 else { return }
                // seek 完了前、および実時刻が seek の目標に着く前は上書きしない
                // （15 秒戻るが元の時刻へ跳ね返る・スライダーびよよーん防止）。
                guard self.acceptsTimeSample(secs) else { return }
                if self.isInBackground {
                    // SwiftData 更新と @Observable の通知を止める（WAL / SwiftUI の jetsam 回避）。
                    self.inMemoryPlaybackPosition = secs
                    return
                }
                // `playbackPosition` は persist 時だけ SwiftData に書く。
                self.currentTime = secs
                if self.isPlaying, self.playbackChrome.nowPlayingEpisodeID != nil {
                    let second = Int(secs.rounded(.down))
                    if second != self.lastChromeLiveTimePublishSecond {
                        self.lastChromeLiveTimePublishSecond = second
                        self.playbackChrome.liveDisplayTime = secs
                    }
                }
            }
        }
    }

    private func attachEndObserver(for item: AVPlayerItem, generation: Int) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onPlaybackEnded(generation: generation)
            }
        }
    }

    private func removeEndObserver() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }

    private func attachStalledObserver(for item: AVPlayerItem) {
        removeStalledObserver()
        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackStall()
            }
        }
    }

    private func removeStalledObserver() {
        if let obs = stalledObserver {
            NotificationCenter.default.removeObserver(obs)
            stalledObserver = nil
        }
    }

    private func attachItemStatusObserver(for item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            guard let item else { return }
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, status == .failed, self.isPlaying else { return }
                // 失敗した瞬間の再生位置を確定させる。
                // reloadCurrentStreamPreservingState 経由なら replaceCurrentItem 前に保存した
                // pendingReloadResumeAt を使う。直接失敗した場合は currentTime を使う。
                // （replaceCurrentItem 後に player.currentTime() が 0 を返し currentTime が
                //  汚染されることがあるため、pendingReloadResumeAt が信頼できる）
                let capturedAt: TimeInterval
                if self.pendingReloadResumeAt >= 0 {
                    capturedAt = self.pendingReloadResumeAt
                } else {
                    capturedAt = self.isInBackground ? self.inMemoryPlaybackPosition : self.currentTime
                }
                if self.finishInsteadOfRecoveringIfNearEnd(at: capturedAt, reason: "item-failed") { return }
                bgLog.info("⚠️ item.status=.failed capturedAt=\(capturedAt)s pendingReload=\(self.pendingReloadResumeAt) isSeeking=\(self.isSeeking) currentTime=\(self.currentTime) → starting network recovery monitor")
                // ネットワーク復帰待ちの間、実際には無音なのに isPlaying=true のまま NowPlayingInfo が
                // rate=1 を書き続けないよう、ここで CC/LS/アプリ UI 向けの表示だけを補正する。
                self.isNetworkStalled = true
                self.nowPlayingSync.applyNowPlayingInfo()
                self.startNetworkRecoveryMonitor(resumeAt: capturedAt)
            }
        }
    }

    private func removeItemStatusObserver() {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
    }

    /// item が failed になったとき、ネットワーク復帰を待って自動リロードする。
    /// `resumeAt` は失敗時点で確定した再生位置。NWPathMonitor は起動直後に現在のパス状態を
    /// コールバックするため、すでにオンラインなら即座にリロードが走る。
    private func startNetworkRecoveryMonitor(resumeAt capturedPosition: TimeInterval) {
        stopNetworkRecoveryMonitor()
        let monitor = NWPathMonitor()
        networkRecoveryMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let episode = self.currentEpisode, let context = self.modelContext else {
                    self.stopNetworkRecoveryMonitor()
                    return
                }
                let itemFailed = self.player?.currentItem?.status == .failed
                let needsRecovery = self.isPlaying || self.player == nil || itemFailed
                guard needsRecovery else {
                    self.stopNetworkRecoveryMonitor()
                    return
                }
                // 連打防止: 直前のリロードから 5 秒以上経過していなければスキップ。
                let now = ProcessInfo.processInfo.systemUptime
                guard now - self.lastNetworkRecoveryUptime >= 5 else {
                    self.stopNetworkRecoveryMonitor()
                    return
                }
                self.lastNetworkRecoveryUptime = now
                bgLog.info("▶️ network recovered → reloading from \(capturedPosition)s currentTime=\(self.currentTime) inMemPos=\(self.inMemoryPlaybackPosition)")
                self.stopNetworkRecoveryMonitor()
                let isBookmarkedLocal = episode.audioURL.hasPrefix("localfile://")
                    || episode.audioURL.hasPrefix("localfolder://")
                if self.player == nil && isBookmarkedLocal {
                    self.beginPlayback(episode: episode, context: context, queueContext: self.queueContext)
                    return
                }
                guard self.isPlaying, itemFailed else { return }
                if self.finishInsteadOfRecoveringIfNearEnd(at: capturedPosition, reason: "network-recovery") { return }
                self.reloadCurrentStreamPreservingState(episode: episode, forcedResumeAt: capturedPosition)
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    private func stopNetworkRecoveryMonitor() {
        networkRecoveryMonitor?.cancel()
        networkRecoveryMonitor = nil
    }

    private func attachTimeControlObserver() {
        timeControlObserver?.invalidate()
        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new]) { p, _ in
            let status   = p.timeControlStatus
            let errMsg   = p.error?.localizedDescription
                        ?? p.currentItem?.error?.localizedDescription
                        ?? "nil"
            let waitDesc = p.reasonForWaitingToPlay?.rawValue ?? "nil"
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .playing:
                    self.nowPlayingSync.logNowPlayingEvent("timeControl", trigger: "observer", extra: "status=playing")
                    // 実際に音が流れ始めたので、読み込み直しの回数と「配信元が遅い」をいったん戻す。
                    // 遅いままなら次の待ちでまた測って分かる。
                    self.resetStallTracking()
                    // 実際に音が流れ始めたので、ネットワーク復帰待ち中に補正していた表示をもとに戻す。
                    self.isNetworkStalled = false
                    self.refreshWaitingIndicator()
                    if !self.isPlaying {
                        // isPlaying=false なのに AVPlayer が再生状態に遷移した（バッファ補充後の自動再開など）。
                        // 直ちに停止させないと iOS の自動 NowPlayingInfo 更新が rate=1 を書き続ける。
                        self.nowPlayingSync.warnNowPlayingMismatch("truth=paused,av.timeControl=playing", event: "timeControl", trigger: "observer")
                        self.player?.pause()
                        self.player?.rate = 0
                        self.nowPlayingSync.scheduleNowPlayingReassert()
                    }
                    self.nowPlayingSync.applyNowPlayingInfo()
                case .paused:
                    self.nowPlayingSync.logNowPlayingEvent("timeControl", trigger: "observer", extra: "status=paused error=\(errMsg)")
                    if self.isPlaying {
                        // 再生するつもりなのに止まっている（読み込み直しの途中で seek が終わらない等）。
                        // ここで見張りを外すと、そのまま固まるので続ける。
                        self.scheduleWaitingStallWatchdogIfNeeded()
                    } else {
                        self.cancelWaitingStallWatchdog()
                    }
                    self.refreshWaitingIndicator()
                    if self.isPlaying {
                        self.nowPlayingSync.warnNowPlayingMismatch("truth=playing,av.timeControl=paused error=\(errMsg)", event: "timeControl", trigger: "observer")
                    }
                    // AVPlayer の遷移後に即 rate=0 を再書き込みし、自動更新による上書きを防ぐ。
                    self.nowPlayingSync.applyNowPlayingInfo()
                case .waitingToPlayAtSpecifiedRate:
                    self.nowPlayingSync.logNowPlayingEvent("timeControl", trigger: "observer", extra: "status=waiting reason=\(waitDesc)")
                    self.refreshWaitingIndicator()
                    // バッファリング中も再生意図 (rate=1) を維持する。
                    // iOS がこの状態を見て rate=0 を NowPlayingInfo に書くことがあるため即座に上書きする。
                    if self.isPlaying {
                        self.nowPlayingSync.applyNowPlayingInfo()
                        // waiting のまま戻らない（stuck buffering）と実際には音が止まっているのに
                        // isPlaying=true・rate=1 が書かれ続けるため、監視を開始する。
                        self.scheduleWaitingStallWatchdogIfNeeded()
                    }
                @unknown default:
                    break
                }
            }
        }
        // player.rate の変化を監視: isPlaying=false なのに rate>0 になったら実際に停止させる。
        rateObserver?.invalidate()
        rateObserver = player?.observe(\.rate, options: [.new]) { [weak self] _, change in
            let newRate = change.newValue ?? 0
            guard newRate > 0 else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isPlaying else { return }
                // isPlaying=false なのに player.rate が上がった（バッファ補充後の自動再開など）。
                // NowPlayingInfo を書き直すだけでは実際の再生が止まらず「表示は paused だが
                // 音は鳴り続ける」desync を起こすため、ここで確実に一時停止させる。
                self.nowPlayingSync.warnNowPlayingMismatch("truth=paused,av.rate=\(newRate)", event: "player.rate", trigger: "observer")
                self.player?.pause()
                self.player?.rate = 0
                self.nowPlayingSync.applyNowPlayingInfo()
                self.nowPlayingSync.scheduleNowPlayingReassert()
            }
        }
    }

    /// 「接続待ち」の表示を今の状態に合わせる。止めた・鳴り始めたらすぐ消す。
    private func refreshWaitingIndicator() {
        guard isPlaying else {
            setWaitingForConnection(false)
            return
        }
        if isNetworkStalled {
            setWaitingForConnection(true)
            return
        }
        guard player?.timeControlStatus == .waitingToPlayAtSpecifiedRate else {
            setWaitingForConnection(false)
            return
        }
        guard !isWaitingForConnection, waitingIndicatorTask == nil else { return }
        waitingIndicatorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            self.waitingIndicatorTask = nil
            if self.isPlaying, self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                self.isWaitingForConnection = true
            }
        }
    }

    private func setWaitingForConnection(_ value: Bool) {
        if !value {
            waitingIndicatorTask?.cancel()
            waitingIndicatorTask = nil
        }
        if isWaitingForConnection != value { isWaitingForConnection = value }
    }

    private func removeTimeControlObserver() {
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil
        cancelWaitingStallWatchdog()
    }

    /// 音が出ないままの待ちを見張る。既に見張っていれば何もしない
    /// （waiting イベントは同じ状態のまま何度も届くため、そのたびに延長しない）。
    /// 読み込み直したあとは状態が「待ち」のまま変わらず KVO が来ないことがあるので、
    /// 読み込み直しの側からも直接呼んで見張りを続ける。
    private func scheduleWaitingStallWatchdogIfNeeded(timeout: TimeInterval? = nil) {
        guard waitingStallWatchdogTask == nil else { return }
        let index = min(stallRetryCount, Self.stallRetryTimeouts.count - 1)
        let wait = timeout ?? Self.stallRetryTimeouts[index]
        waitingStallWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            self.waitingStallWatchdogTask = nil
            // 読み込み直しの直後は .paused のこともあるので、「流れていない」で判断する。
            guard self.isPlaying, self.player?.timeControlStatus != .playing else { return }
            self.handleWaitingTimeout(after: wait)
        }
    }

    private func cancelWaitingStallWatchdog() {
        waitingStallWatchdogTask?.cancel()
        waitingStallWatchdogTask = nil
    }

    /// 読み込み直しの回数・「配信元が遅い」・見張りを最初の状態に戻す。
    private func resetStallTracking() {
        stallRetryCount = 0
        slowWaitStartedUptime = nil
        isSourceSlow = false
        cancelWaitingStallWatchdog()
    }

    /// 音が出ないまま [wait] 秒たったときの判断。
    /// - 配信元が遅いだけなら、読み込み直さずに待ち続ける（画面に「配信元が遅い」を出す）。
    /// - そうでなければ、間隔を延ばしながら読み込み直す。
    /// - どちらも限度を超えたら、止めて知らせる（「接続待ち…」のまま放置しない）。
    private func handleWaitingTimeout(after wait: TimeInterval) {
        if finishInsteadOfRecoveringIfNearEnd(at: latestKnownPlaybackPosition(), reason: "waiting-stall") { return }
        isNetworkStalled = true
        nowPlayingSync.applyNowPlayingInfo()

        if let rates = measuredTransferRates(), rates.observed < rates.required * 0.8 {
            let now = ProcessInfo.processInfo.systemUptime
            if !isSourceSlow {
                bgLog.warning("🐢 slow source: observed=\(Int(rates.observed / 1000))kbps required=\(Int(rates.required / 1000))kbps — waiting without reload")
            }
            isSourceSlow = true
            let startedAt = slowWaitStartedUptime ?? (now - wait)
            slowWaitStartedUptime = startedAt
            if now - startedAt >= Self.slowSourceGiveUpAfter {
                giveUpStalledPlayback(notice: .sourceTooSlow)
                return
            }
            scheduleWaitingStallWatchdogIfNeeded(timeout: Self.slowSourceRecheckInterval)
            return
        }

        guard stallRetryCount < Self.maxStallRetries else {
            giveUpStalledPlayback(notice: .stalledGaveUp)
            return
        }
        stallRetryCount += 1
        bgLog.warning("⚠️ waiting-stall: no audio for \(wait)s — reload \(self.stallRetryCount)/\(Self.maxStallRetries)")
        handlePlaybackStall()
    }

    /// 配信元からの転送の速さと、再生に必要な速さ（どちらも bit/s）。
    /// データがまったく届いていない（＝遅いのではなく繋がらない）ときや、まだ測れないときは nil。
    ///
    /// MP3 などの通常のファイル配信では accessLog の transferDuration が 0 のままなので使わない。
    /// observedBitrate（AVPlayer が測った転送の速さ）を使い、無ければ
    /// 「届いたバイト数 ÷ この item を作ってからの時間」で割り出す。
    private func measuredTransferRates() -> (observed: Double, required: Double)? {
        guard let events = player?.currentItem?.accessLog()?.events, let last = events.last else { return nil }
        let bytes = events.reduce(Int64(0)) { $0 + max($1.numberOfBytesTransferred, 0) }
        guard bytes > 0 else { return nil }
        let required = requiredBitrate ?? Self.fallbackRequiredBitrate
        if last.observedBitrate.isFinite, last.observedBitrate > 0 {
            return (last.observedBitrate, required)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - currentItemStartedUptime
        guard elapsed >= 5 else { return nil }
        return (Double(bytes) * 8 / elapsed, required)
    }

    /// 読み込めないまま限度を超えたので止め、画面に理由を出す。
    private func giveUpStalledPlayback(notice: PlaybackNotice) {
        bgLog.warning("⛔️ giving up stalled playback: \(String(describing: notice)) retries=\(self.stallRetryCount)")
        cancelWaitingStallWatchdog()
        pausePlayback(trigger: "stall-give-up")
        playbackNotice = notice
    }

    /// 末尾までの残りがこれ以下で読み込みが止まったら、巻き戻して読み込み直さず、終わりとして扱う。
    /// 保存位置は再生ヘッドより最大 10 秒ほど古いので、読み込み直すと同じ outro がもう一度鳴る。
    private static let nearEndThreshold: TimeInterval = 15

    /// いま分かっている一番新しい再生位置。seek 中でなければ AVPlayer の実時刻も見る。
    private func latestKnownPlaybackPosition() -> TimeInterval {
        let base = isInBackground ? inMemoryPlaybackPosition : currentTime
        guard !isSeeking, pendingSeekTarget == nil,
              let player, player.currentItem?.status != .failed else { return base }
        let live = player.currentTime().seconds
        guard live.isFinite, live >= 0 else { return base }
        return max(base, live)
    }

    private func isNearPlaybackEnd(_ position: TimeInterval) -> Bool {
        let total = duration > 0 ? duration : (currentEpisode?.totalDuration ?? 0)
        guard total > 0 else { return false }
        return total - position <= Self.nearEndThreshold
    }

    /// 終わり付近の stall・失敗は、読み込み直さずにエピソードの終わりとして 1 回だけ処理する。
    /// - Returns: 終わりとして処理した（または処理済みだった）ら true。呼び出し側は復帰をしない。
    private func finishInsteadOfRecoveringIfNearEnd(at position: TimeInterval, reason: String) -> Bool {
        if didReachPlaybackEnd { return true }
        guard isNearPlaybackEnd(position) else { return false }
        bgLog.info("🏁 \(reason, privacy: .public) near end at \(position)s / \(self.duration)s → finish without reload")
        onPlaybackEnded(generation: playbackGeneration)
        return true
    }

    private func handlePlaybackStall() {
        guard isPlaying, let episode = currentEpisode else { return }
        if finishInsteadOfRecoveringIfNearEnd(at: latestKnownPlaybackPosition(), reason: "stall") { return }
        // 配信元が遅いだけのときは、読み込み直すと読み込み済みの分を捨てて最初の待ちからやり直すので不利。
        if isSourceSlow {
            scheduleWaitingStallWatchdogIfNeeded(timeout: Self.slowSourceRecheckInterval)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let sinceLast = now - lastStalledReloadUptime
        guard sinceLast > 10 else {
            // 見送るだけだと、その後だれも試し直さず「接続待ち…」のまま固まるので、間を空けて見張り直す。
            bgLog.warning("⚠️ stall: reload deferred (cooldown)")
            scheduleWaitingStallWatchdogIfNeeded(timeout: max(10 - sinceLast, 1))
            return
        }
        lastStalledReloadUptime = now
        bgLog.warning("⚠️ stall detected at \(self.currentTime)s — reloading stream")
        reloadCurrentStreamPreservingState(episode: episode)
    }

    private func loadDurationFromAssetIfNeeded(generation: Int) async {
        guard let asset = player?.currentItem?.asset else { return }
        guard let cmDur = try? await asset.load(.duration),
              cmDur.seconds.isFinite, cmDur.seconds > 0 else { return }
        // await 中にエピソードが切り替わっていたら、古い duration を新エピソードへ書き込まない。
        guard playbackGeneration == generation else { return }
        self.duration = cmDur.seconds
        self.currentEpisode?.totalDuration = cmDur.seconds
        if !isInBackground { try? self.modelContext?.save() }
        self.nowPlayingSync.updateNowPlaying()
        // 「配信元が遅い」の判断に使う、再生に必要な速さ。
        if requiredBitrate == nil,
           let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let rate = try? await track.load(.estimatedDataRate), rate > 0,
           playbackGeneration == generation {
            requiredBitrate = Double(rate)
        }
    }

    private func applySeek(to seconds: TimeInterval) {
        if isInBackground {
            inMemoryPlaybackPosition = seconds
        } else {
            currentTime = seconds
            currentEpisode?.playbackPosition = seconds
            if isPlaying { playbackChrome.liveDisplayTime = seconds }
        }
        guard player != nil else {
            // 完了コールバックが来ないので isSeeking を立てない。保存位置から、あとで再生を始める。
            isSeeking = false
            pendingSeekTarget = nil
            inMemoryPlaybackPosition = seconds
            currentEpisode?.playbackPosition = seconds
            nowPlayingSync.updateNowPlaying(elapsed: seconds)
            return
        }
        startTrackedSeek(to: seconds)
        nowPlayingSync.updateNowPlaying(elapsed: seconds)
    }

    /// AVPlayer を seek し、完了まで（＋実時刻が目標付近になるまで）周期サンプルでの上書きを止める。
    /// 古い seek の完了は、新しい seek の状態を変えない。
    private func startTrackedSeek(
        to seconds: TimeInterval,
        onFinished: (@MainActor (_ finished: Bool, _ isLatestSeek: Bool) -> Void)? = nil
    ) {
        guard let player else { return }
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        pendingSeekTarget = seconds
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isLatestSeek = self.seekGeneration == generation
                if isLatestSeek {
                    self.isSeeking = false
                    self.seekCompletedUptime = ProcessInfo.processInfo.systemUptime
                    if !finished {
                        // 中断された seek は目標に着かない。目標待ちを残すと時刻が止まる。
                        self.pendingSeekTarget = nil
                    }
                }
                onFinished?(finished, isLatestSeek)
            }
        }
    }

    /// 周期サンプルを時刻として採用してよいか。seek 中や、seek 前の位置のままのサンプルは捨てる。
    private func acceptsTimeSample(_ seconds: TimeInterval) -> Bool {
        guard !isSeeking else { return false }
        guard let target = pendingSeekTarget else { return true }
        if abs(seconds - target) <= Self.seekArrivalTolerance
            || ProcessInfo.processInfo.systemUptime - seekCompletedUptime >= Self.seekArrivalTimeout {
            pendingSeekTarget = nil
            return true
        }
        return false
    }

    // MARK: - Local Folder Bookmark

    /// Resolves a `localfile://key` or `localfolder://key/filename` audioURL to a playable file URL.
    /// Starts security-scoped access and stores it in `activeFolderAccess`.
    private func resolveLocalFolderURL(for episode: Episode) -> URL? {
        let audioURL = episode.audioURL

        // Per-file bookmark (localfile://bookmarkKey)
        if audioURL.hasPrefix("localfile://") {
            let key = String(audioURL.dropFirst("localfile://".count))
            // Ignore localfile://show/... identifiers (show-level feed URLs, not file URLs)
            guard !key.hasPrefix("show/"), !key.isEmpty else { return nil }
            stopActiveFolderAccess()
            guard let fileURL = LocalFolderBookmarkStore.resolveURL(for: key) else { return nil }
            let accessed = fileURL.startAccessingSecurityScopedResource()
            activeFolderAccess = (url: fileURL, accessed: accessed)
            return fileURL
        }

        // Per-folder bookmark with filename suffix (localfolder://bookmarkKey/filename)
        let prefix = "localfolder://"
        guard audioURL.hasPrefix(prefix) else { return nil }
        let withoutScheme = String(audioURL.dropFirst(prefix.count))
        guard let slashIndex = withoutScheme.firstIndex(of: "/") else { return nil }
        let bookmarkKey = String(withoutScheme[..<slashIndex])
        let filename = String(withoutScheme[withoutScheme.index(after: slashIndex)...])
        guard !bookmarkKey.isEmpty, !filename.isEmpty else { return nil }

        stopActiveFolderAccess()
        guard let folderURL = LocalFolderBookmarkStore.resolveURL(for: bookmarkKey) else { return nil }
        let accessed = folderURL.startAccessingSecurityScopedResource()
        activeFolderAccess = (url: folderURL, accessed: accessed)
        return folderURL.appendingPathComponent(filename)
    }

    private func stopActiveFolderAccess() {
        if let access = activeFolderAccess, access.accessed {
            access.url.stopAccessingSecurityScopedResource()
        }
        activeFolderAccess = nil
    }

    // MARK: - Teardown

    private func teardownPlayer() {
        // プレイヤー破棄後は再生が続かないため、バックグラウンド中でも強制フラッシュする。
        persistPosition(force: true)
        stopActiveFolderAccess()
        player?.pause()
        isPlaying = false
        isNetworkStalled = false
        syncPlaybackChrome()
        syncPlaybackActivityFlag()
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        removeEndObserver()
        removeStalledObserver()
        removeTimeControlObserver()
        removeItemStatusObserver()
        stopNetworkRecoveryMonitor()
        pendingReloadResumeAt = -1
        // 破棄する player の seek 完了は来ないか、来ても古い。次の player に持ち越さない。
        seekGeneration += 1
        isSeeking = false
        pendingSeekTarget = nil
        saveTask?.cancel()
        saveTask = nil
        backgroundNowPlayingTask?.cancel()
        backgroundNowPlayingTask = nil
        nowPlayingSync.teardown()
        player = nil
        queueContext = .none
        invalidatePlaybackAudioSessionState()
    }

    private func onPlaybackEnded(generation: Int) {
        // 同じ再生で終わり処理は 1 回だけ。遅れて届いた終了通知や別エピソードの通知では動かない。
        guard generation == playbackGeneration, !didReachPlaybackEnd else { return }
        guard let finishedEpisode = currentEpisode else { return }

        if isRepeatEnabled {
            let t = CMTime(seconds: 0, preferredTimescale: 600)
            player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = 0
            currentEpisode?.playbackPosition = 0
            playCurrentItem()
            isPlaying = true
            syncPlaybackChrome(liveTime: currentTime)
            syncPlaybackActivityFlag()
            if isInBackground {
                startBackgroundPositionTracking()
            } else {
                startPeriodicSave()
            }
            nowPlayingSync.updateNowPlaying()
            return
        }

        player?.pause()
        isPlaying = false
        syncPlaybackChrome()
        syncPlaybackActivityFlag()
        saveTask?.cancel()
        backgroundNowPlayingTask?.cancel()
        backgroundNowPlayingTask = nil
        currentEpisode?.isPlayed = true
        currentEpisode?.playbackPosition = 0
        currentTime = 0
        inMemoryPlaybackPosition = 0
        didReachPlaybackEnd = true
        // 終わったあとの stall 復帰・ネットワーク復帰で、末尾をもう一度鳴らさない。
        cancelWaitingStallWatchdog()
        stopNetworkRecoveryMonitor()
        isNetworkStalled = false
        pendingReloadResumeAt = -1
        finishedEpisode.clearNewIndicator()
        if !isInBackground { try? modelContext?.save() }
        nowPlayingSync.updateNowPlaying(elapsed: 0)
        enqueueNextEpisode(after: finishedEpisode)
        // 次のエピソードが見つからず再生が完全に止まった場合はオーディオセッションを手放す。
        // これにより Spotify など他のオーディオアプリが音声セッションを取得しやすくなる。
        if !isPlaying && !isInBackground {
            releasePlaybackAudioSession(notifyOthers: true)
        }
    }

    /// - Parameter force: バックグラウンド中でも即座にディスクへ書く。
    ///   再生が完全に止まる（＝この後いつフォアグラウンドに戻るか分からない）チェックポイントでのみ true を渡す。
    ///   通常の周期保存は false のままにし、頻繁な WAL 書き込みによる iOS の SIGKILL を避ける。
    private func persistPosition(force: Bool = false) {
        guard let ep = currentEpisode else { return }
        let position = isInBackground ? inMemoryPlaybackPosition : currentTime
        ep.playbackPosition = position
        ep.clearNewIndicatorIfPlaybackEngaged()
        // バックグラウンド中は force が指定されない限りディスク書き込みを行わない。
        // WAL への書き込みが積み重なると iOS が SIGKILL することがある。
        // フォアグラウンド復帰時に saveContextNow() で一括フラッシュする。
        guard !isInBackground || force else { return }
        try? modelContext?.save()
    }

    private func saveContextNow() {
        try? modelContext?.save()
    }

    private func startPeriodicSave() {
        saveTask?.cancel()
        saveTask = Task {
            var tickCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                persistPosition()
                tickCount += 1
                // フォアグラウンド再生中は状態遷移時のバースト再同期しか行っていないため、
                // 何もトリガーが起きないまま長時間再生し続けると CC の表示ズレを自己修復できない。
                // バックグラウンド側の 30 秒周期（startBackgroundPositionTracking）と揃えて
                // フォアグラウンドでも同じ間隔でエッジ強制付きの再同期を行う。
                if tickCount % 3 == 0, isPlaying {
                    await nowPlayingSync.forceNowPlayingRateEdge(elapsed: nil, expectedPlaying: true)
                }
            }
        }
    }

    /// 互換性優先で最小構成。mode / 追加オプションは SessionCore エラーを誘発しやすい。
    private func preparePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if !didApplyPlaybackCategory {
                try session.setCategory(.playback, mode: .default, options: [])
                didApplyPlaybackCategory = true
            }
            try session.setActive(true, options: [])
            playbackAudioSessionIsActive = true
            bgLog.info("✅ session active. category=\(session.category.rawValue) route=\(session.currentRoute.outputs.first?.portName ?? "none")")
        } catch {
            bgLog.error("❌ setActive failed: \(error)")
            didApplyPlaybackCategory = false
            try? session.setCategory(.playback, mode: .default, options: [])
            didApplyPlaybackCategory = true
            do {
                try session.setActive(true, options: [])
                playbackAudioSessionIsActive = true
            } catch {
                playbackAudioSessionIsActive = false
                bgLog.error("❌ setActive retry failed: \(error)")
            }
        }
    }

    private func invalidatePlaybackAudioSessionState() {
        didApplyPlaybackCategory = false
    }

    private func setupSessionObservers() {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let typeRaw   = notification.userInfo?[AVAudioSessionInterruptionTypeKey]   as? UInt
            let optionRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            let reasonRaw = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.applyInterruption(typeRaw: typeRaw, optionRaw: optionRaw, reasonRaw: reasonRaw)
            }
        }

        // イヤホン抜去・Bluetooth切断などのルート変更
        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.applyRouteChange(reasonRaw: reasonRaw)
            }
        }
    }

    private func setupApplicationLifecycleObservers() {
        let center = NotificationCenter.default
        appWillResignActiveObserver = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.capturePlaybackIntentAtSuspension()
            }
        }
        appDidEnterBackgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidEnterBackground()
            }
        }
        appWillEnterForegroundObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notifyAppBecameActiveForRecovery()
            }
        }
        memoryWarningObserver = center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            // メモリキャッシュを解放して jetsam kill を回避する。ディスクキャッシュは保持。
            Task { await ThumbnailImageCache.shared.purgeMemory() }
            bgLog.warning("⚠️ memory warning: purged thumbnail memory cache")
        }
    }

    /// `willResignActive` はまだフォアグラウンドの延長なので、ここでディスクへ書く。
    /// `didEnterBackground` 以降は一切ディスク書き込みを行わない。
    private func capturePlaybackIntentAtSuspension() {
        nowPlayingSync.logNowPlayingEvent("app.resignActive", trigger: "lifecycle")
        if isPlaying, let ep = currentEpisode {
            let position = max(currentTime, inMemoryPlaybackPosition)
            currentTime = position
            ep.playbackPosition = position
            saveContextNow()
            bgLog.info("willResignActive: flushed position=\(self.currentTime)")
        }
    }

    /// バックグラウンド確定後はディスク書き込みを完全に停止する。
    private func handleDidEnterBackground() {
        nowPlayingSync.logNowPlayingEvent("app.background", trigger: "lifecycle")
        inMemoryPlaybackPosition = currentTime
        isInBackground = true
        saveTask?.cancel()
        saveTask = nil
        nowPlayingSync.cancelArtworkLoading()
        if isPlaying {
            startBackgroundPositionTracking()
            Task { await ThumbnailImageCache.shared.purgeMemory() }
            bgLog.info("didEnterBackground: kept audio session active, paused non-playback work")
        } else if currentEpisode != nil, playbackAudioSessionIsActive {
            // すでに止まっているのにセッションが残っていると、CC だけ ⏸ のままになる。
            // バックグラウンドへ入る時点で手放す。他アプリの再開通知はしない。
            nowPlayingSync.applyNowPlayingInfo()
            releasePlaybackAudioSession(notifyOthers: false)
        }
    }

    /// バックグラウンド中の再生位置だけを低頻度で更新（SwiftData は触らない）。
    private func startBackgroundPositionTracking() {
        backgroundNowPlayingTask?.cancel()
        backgroundNowPlayingTask = Task { [weak self] in
            var tickCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                guard let self, self.isInBackground, self.isPlaying else { break }
                // failed item は currentTime() が 0 などの不正値を返すため、
                // 上書きせず最後に記録した正しい位置を保持する。
                if self.player?.currentItem?.status == .failed { break }
                let raw = self.player?.currentTime().seconds ?? self.inMemoryPlaybackPosition
                // ロック画面の 15 秒戻るの直後は、seek 前の位置で上書きしない。
                if raw.isFinite, raw >= 0, self.acceptsTimeSample(raw) {
                    self.inMemoryPlaybackPosition = raw
                }
                tickCount += 1
                // ロック画面のタイマーが古くなるのを防ぐため 30 秒ごとに NowPlayingInfo を再書き込みする。
                // iOS は rate=1 で自動進行するが、バッファリング復帰などで基準時刻がずれる場合がある。
                // 単純な再書き込みだけでは CC の再生ボタンの再描画が起きないことがあるため、
                // エッジ強制（0→1）付きの再同期を使う。
                if tickCount % 6 == 0 {
                    await self.nowPlayingSync.forceNowPlayingRateEdge(elapsed: self.inMemoryPlaybackPosition, expectedPlaying: true)
                }
            }
        }
    }

    private func handleReturnedToForegroundDebounced() {
        guard !didReachPlaybackEnd else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastForegroundRecoveryUptime < 0.75 {
            nowPlayingSync.logNowPlayingEvent("app.foreground", trigger: "lifecycle", extra: "debounced=true")
            return
        }
        lastForegroundRecoveryUptime = now
        nowPlayingSync.logNowPlayingEvent("app.foreground", trigger: "lifecycle", extra: "debounced=false")

        backgroundNowPlayingTask?.cancel()
        backgroundNowPlayingTask = nil
        isInBackground = false
        // `inMemoryPlaybackPosition` は5秒間隔のポーリングでしか更新されないため、
        // 5秒未満で復帰した場合は backgrounded 時点のスナップショットのまま古くなっている。
        // それを使って currentTime を上書きすると、実際の再生位置より手前に巻き戻ってしまう
        // （稀に発生する「再生が勝手に戻る」不具合の原因）。AVPlayer の実時刻を直接読み直す。
        // ただし failed item は currentTime() が 0 などの不正値を返すため読み直さない。
        // バックグラウンドトラッカーが item 失敗前の最終正常値を inMemoryPlaybackPosition に保持している。
        // seek が終わる前（ロック画面の 15 秒戻る直後など）は、seek 前の位置を読んでしまうので読み直さない。
        if player?.currentItem?.status != .failed,
           let raw = player?.currentTime().seconds, raw.isFinite, raw >= 0,
           acceptsTimeSample(raw) {
            inMemoryPlaybackPosition = raw
        }
        if inMemoryPlaybackPosition > 0 {
            currentTime = inMemoryPlaybackPosition
        }
        // バックグラウンド中に更新されたインメモリ位置をディスクにフラッシュする。
        persistPosition()

        if let episode = currentEpisode {
            nowPlayingSync.refreshNowPlayingArtwork(for: episode)
        }

        // フォアグラウンド復帰時は現在位置で NowPlayingInfo を即時更新する。
        // バックグラウンド中に elapsed が古いまま固まっていた場合もここでリセットされる。
        nowPlayingSync.updateNowPlaying()

        guard isPlaying else {
            // バックグラウンド中にセッションを手放し損ねたとき、復帰で CC の ⏸ を下ろす。
            // すでに手放していれば何もしない（setActive の連打はクリックノイズになる）。
            if playbackAudioSessionIsActive {
                releasePlaybackAudioSession(notifyOthers: false)
            }
            return
        }
        startPeriodicSave()
        // isPlaying はユーザーの再生意図を保持する。rate=0 はプレイヤーが予期せず停止した証拠。
        if player?.rate == 0 {
            nowPlayingSync.warnNowPlayingMismatch("truth=playing,av.rate=0 on foreground return", event: "app.foreground", trigger: "lifecycle")
            resumePlaybackAfterUnexpectedPause(minimumCooldown: 0.5)
        }
    }

    private func reloadCurrentStreamPreservingState(episode: Episode, forcedResumeAt: TimeInterval? = nil) {
        // 終わり処理のあとに届いた復帰で、末尾へ巻き戻して再生し直さない。
        guard !didReachPlaybackEnd else { return }
        guard let url = resolvePlaybackURL(for: episode), player != nil else { return }

        // forcedResumeAt が指定された場合はそれを優先する（ネットワーク復帰リロード時など、
        // currentTime / inMemoryPlaybackPosition が復帰待ち中に壊れている可能性がある場合）。
        // 未指定の場合はバックグラウンド中は inMemoryPlaybackPosition、フォアグラウンドは currentTime を使う。
        let basePosition = isInBackground ? inMemoryPlaybackPosition : currentTime
        let resumeAt = max(forcedResumeAt ?? basePosition, 0)
        // replaceCurrentItem 前に確定した位置を記録する。
        // attachItemStatusObserver が item 失敗をキャプチャする時点では currentTime が
        // 0 に汚染されている可能性があるため、ここで保存した値を優先して使う。
        pendingReloadResumeAt = resumeAt

        persistPosition()
        removeEndObserver()

        let isBookmarkedLocal = episode.audioURL.hasPrefix("localfile://")
            || episode.audioURL.hasPrefix("localfolder://")

        if isBookmarkedLocal {
            let generation = playbackGeneration
            Task { [weak self] in
                guard let self else { return }
                let needsOverlay = await BookmarkedFilePlaybackPreparer.needsPreparation(at: url)
                if needsOverlay {
                    self.cloudFilePreparation.begin(fileName: url.lastPathComponent)
                }
                defer {
                    if needsOverlay {
                        self.cloudFilePreparation.end()
                    }
                }
                let prepared = await self.prepareBookmarkedFileIfNeeded(
                    url: url,
                    generation: generation,
                    resumeAt: resumeAt
                )
                guard prepared, self.playbackGeneration == generation else { return }
                self.replaceCurrentPlayerItem(
                    url: url,
                    episode: episode,
                    resumeAt: resumeAt,
                    generation: generation
                )
                let ready = await self.waitForPlayerItemReady(generation: generation)
                if !ready, self.isPlaying {
                    self.player?.pause()
                    self.isPlaying = false
                    self.syncPlaybackChrome()
                    self.syncPlaybackActivityFlag()
                    self.nowPlayingSync.syncRemoteCommandsAvailability()
                    self.nowPlayingSync.updateNowPlaying()
                    self.startNetworkRecoveryMonitor(resumeAt: resumeAt)
                }
            }
            return
        }

        replaceCurrentPlayerItem(
            url: url,
            episode: episode,
            resumeAt: resumeAt,
            generation: playbackGeneration
        )
    }

    private func replaceCurrentPlayerItem(
        url: URL,
        episode: Episode,
        resumeAt: TimeInterval,
        generation: Int
    ) {
        guard let player else { return }

        let isBookmarkedLocal = episode.audioURL.hasPrefix("localfile://")
            || episode.audioURL.hasPrefix("localfolder://")
        let isLocal = url.isFileURL && !isBookmarkedLocal
        let newItem = makePlayerItem(url: url, isLocalFile: isLocal)
        player.replaceCurrentItem(with: newItem)
        attachEndObserver(for: newItem, generation: generation)
        attachStalledObserver(for: newItem)
        attachItemStatusObserver(for: newItem)
        // 読み込み直しても「待ち」のままだと状態が変わらず KVO が来ないので、ここで見張りを掛け直す。
        if isPlaying {
            cancelWaitingStallWatchdog()
            scheduleWaitingStallWatchdogIfNeeded()
        }
        nowPlayingSync.updateNowPlaying(elapsed: resumeAt)

        Task { [weak self] in
            await self?.loadDurationFromAssetIfNeeded(generation: generation)
        }

        // replaceCurrentItem 後 seek 完了前に周期オブザーバーが time=0 を currentTime に書き込まないよう保護。
        startTrackedSeek(to: resumeAt) { [weak self] finished, isLatestSeek in
            guard let self, self.playbackGeneration == generation else { return }
            bgLog.info("🔍 reload seek finished=\(finished) latest=\(isLatestSeek) resumeAt=\(resumeAt) currentTime=\(self.currentTime) itemStatus=\(self.player?.currentItem?.status.rawValue ?? -1)")
            self.pendingReloadResumeAt = -1
            // 読み込み直しの途中でユーザーが seek したときは、その位置を優先する。
            if isLatestSeek {
                self.currentTime = resumeAt
                self.currentEpisode?.playbackPosition = resumeAt
            }
            // stall 後のリロードでは AVPlayer の rate が 0 になっているため、明示的に再生を再開する。
            // replaceCurrentItem 後にセッションが非アクティブになっていることがあるため再確認する。
            if self.isPlaying {
                self.preparePlaybackAudioSession()
                self.playCurrentItem()
            }
            if isLatestSeek {
                self.nowPlayingSync.updateNowPlaying(elapsed: resumeAt)
                if self.isPlaying {
                    self.nowPlayingSync.scheduleNowPlayingReassert(elapsed: resumeAt)
                }
            }
        }
    }

    private func enqueueNextEpisode(after finishedEpisode: Episode) {
        if isRandomModeEnabled {
            if let nextEpisode = randomModeNextEpisode(after: finishedEpisode) {
                guard let ctx = modelContext else { return }
                play(episode: nextEpisode, context: ctx, queueContext: .none)
                return
            }
            queueContext = .none
            return
        }
        if let nextEpisode = nextEpisodeToAutoPlay(after: finishedEpisode) {
            guard let ctx = modelContext else { return }
            play(episode: nextEpisode, context: ctx, queueContext: .show(finishedEpisode.show.persistentModelID))
            return
        }
        // 番組に次が無いときだけ、設定「別のエピソードを自動再生する」に任せる（オフなら nil で停止）。
        if let nextEpisode = globalAutoPlayNextEpisode(after: finishedEpisode) {
            guard let ctx = modelContext else { return }
            play(episode: nextEpisode, context: ctx, queueContext: .none)
            return
        }
        queueContext = .none
    }

    private func randomModeNextEpisode(after finishedEpisode: Episode) -> Episode? {
        guard let ctx = modelContext else { return nil }
        let excludedFeedURLs = AppSettings.autoPlayExcludedShowFeedURLs
        guard let allShows = try? ctx.fetch(FetchDescriptor<Show>()) else { return nil }
        let finishedID = finishedEpisode.persistentModelID
        let currentID = currentEpisode?.persistentModelID
        let candidates: [Episode] = allShows
            .filter { !excludedFeedURLs.contains($0.feedURL) }
            .flatMap { $0.episodes }
            .filter { $0.persistentModelID != finishedID && $0.persistentModelID != currentID && !$0.isPlayed }
        return candidates.randomElement()
    }

    private func globalAutoPlayNextEpisode(after finishedEpisode: Episode) -> Episode? {
        guard AppSettings.autoPlayEnabled else { return nil }
        guard let ctx = modelContext else { return nil }
        let excludedFeedURLs = AppSettings.autoPlayExcludedShowFeedURLs
        let order = AppSettings.autoPlayOrder
        guard let allShows = try? ctx.fetch(FetchDescriptor<Show>()) else { return nil }
        let finishedShowID = finishedEpisode.show.persistentModelID
        let finishedID = finishedEpisode.persistentModelID
        let sameShowEpisodes: [Episode]
        if excludedFeedURLs.contains(finishedEpisode.show.feedURL) {
            sameShowEpisodes = []
        } else {
            sameShowEpisodes = finishedEpisode.show.episodes.filter { $0.persistentModelID != finishedID }
        }
        let otherShowsEpisodes: [Episode] = allShows
            .filter { $0.persistentModelID != finishedShowID && !excludedFeedURLs.contains($0.feedURL) }
            .flatMap { $0.episodes }

        func pick(from episodes: [Episode]) -> Episode? {
            guard !episodes.isEmpty else { return nil }
            switch order {
            case .newest:
                return episodes.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }.first
            case .oldest:
                return episodes.sorted { ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast) }.first
            case .random:
                return episodes.randomElement()
            }
        }

        let priorityGroups: [[Episode]] = [
            sameShowEpisodes.filter { $0.isNew },
            otherShowsEpisodes.filter { $0.isNew },
            sameShowEpisodes.filter { $0.playbackPosition > 0 && !$0.isPlayed },
            otherShowsEpisodes.filter { $0.playbackPosition > 0 && !$0.isPlayed },
            sameShowEpisodes.filter { !$0.isPlayed && $0.playbackPosition == 0 && !$0.isNew },
            otherShowsEpisodes.filter { !$0.isPlayed && $0.playbackPosition == 0 && !$0.isNew },
            sameShowEpisodes.filter { $0.isPlayed },
            otherShowsEpisodes.filter { $0.isPlayed },
        ]
        for group in priorityGroups {
            if let ep = pick(from: group) { return ep }
        }
        return nil
    }

    /// ランダム再生オフのときの「次」。今の番組の中で、ライブラリの並び（`episodeOrderOption` と昇順／降順）の隣。
    /// 再生した経路（フォルダ・検索・復元）に関係なく同じ番組の中で進み、別の番組には飛ばない。
    /// `publishedAt` が無いエピソードも並びの位置で決める。
    private func nextEpisodeToAutoPlay(after episode: Episode) -> Episode? {
        let ordered = episode.show.sortedEpisodes
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == episode.persistentModelID }) else {
            return nil
        }
        return ordered[(index + 1)...].first {
            !AppSettings.skipPlayedEpisodes || !$0.isPlayed
        }
    }

    /// ユーザー操作以外で再生が止まったときの共通処理（自動再開しない）。
    ///
    /// `notifyOthersOnDeactivation` は、再生を終えて他アプリにセッションを返してよいときだけ true。
    /// 通話・Siri の割り込み開始中は false（通話中に別の再生を起こさない）。
    private func notePlaybackStoppedWithoutUserAction(notifyOthersOnDeactivation: Bool) {
        isPlaying = false
        isNetworkStalled = false
        stopNetworkRecoveryMonitor()
        if isInBackground {
            backgroundNowPlayingTask?.cancel()
            backgroundNowPlayingTask = nil
        }
        syncPlaybackChrome()
        syncPlaybackActivityFlag()
        publishPausedNowPlaying(
            elapsed: nil,
            notifyOthersOnDeactivation: notifyOthersOnDeactivation,
            releaseInBackground: true
        )
    }

    /// 停止をコントロールセンターとロック画面へ届ける。
    ///
    /// オーディオセッションがアクティブなままだと、システムが再生中と推測し、
    /// `playbackState = .paused` を書いても ⏸ が残ることがある。
    /// バックグラウンドのままスピーカーを奪われたときも手放す。
    /// 停止側では再生レートの 0→1 は作らない。一瞬再生中に見えるため。
    private func publishPausedNowPlaying(
        elapsed: TimeInterval?,
        notifyOthersOnDeactivation: Bool,
        releaseInBackground: Bool = false
    ) {
        nowPlayingSync.applyNowPlayingInfo(elapsed: elapsed)
        nowPlayingSync.syncRemoteCommandsAvailability()
        nowPlayingSync.scheduleNowPlayingReassert(elapsed: elapsed)
        if isInBackground, !releaseInBackground { return }
        releasePlaybackAudioSession(notifyOthers: notifyOthersOnDeactivation)
    }

    /// `defaultRate` を 1 に戻してから再生する。停止中は 0 にしてある。
    private func playCurrentItem() {
        guard let player else { return }
        player.defaultRate = 1
        player.play()
    }

    /// すでに止まっているときのリモート一時停止。セッションを手放して CC の ⏸ を下ろす。
    func releasePlaybackAudioSessionFromRemotePause() {
        releasePlaybackAudioSession(notifyOthers: true)
    }

    private func releasePlaybackAudioSession(notifyOthers: Bool) {
        let options: AVAudioSession.SetActiveOptions = notifyOthers ? .notifyOthersOnDeactivation : []
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: options)
            playbackAudioSessionIsActive = false
        } catch {
            bgLog.error("❌ setActive(false) failed: \(error)")
        }
    }

    private func pauseDueToExternalAudio() {
        bgLog.warning("⏸ pauseDueToExternalAudio called (interruption .began)")
        guard player != nil else { return }
        player?.pause()
        notePlaybackStoppedWithoutUserAction(notifyOthersOnDeactivation: false)
        // 割り込み（電話・Siri等）による自動停止。バックグラウンド中でも強制フラッシュする。
        persistPosition(force: true)
        saveTask?.cancel()
        saveTask = nil
    }

    private func applyRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else { return }

        nowPlayingSync.logNowPlayingEvent("routeChange", trigger: "system", extra: "reason=\(reasonRaw)")

        switch reason {
        case .oldDeviceUnavailable:
            // Apple HIG: イヤホン・Bluetooth が外れたら自動で一時停止する
            if isPlaying {
                player?.pause()
                notePlaybackStoppedWithoutUserAction(notifyOthersOnDeactivation: true)
                // イヤホン等の切断による自動停止。バックグラウンド中でも強制フラッシュする。
                persistPosition(force: true)
                saveTask?.cancel()
                saveTask = nil
            }
        case .newDeviceAvailable:
            // 新しいデバイスが接続されても自動再開はしない（ユーザー操作を待つ）
            break
        default:
            break
        }
    }

    private func applyInterruption(typeRaw: UInt?, optionRaw: UInt?, reasonRaw: UInt? = nil) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            // 割り込み開始前に再生していたかを記録（手動停止後の誤った自動再開を防ぐ）
            wasPlayingAtInterruption = isPlaying && player != nil
            nowPlayingSync.logNowPlayingEvent("interruption", trigger: "system", extra: "phase=began reason=\(reasonRaw ?? 0) wasPlaying=\(wasPlayingAtInterruption)")
            pauseDueToExternalAudio()
        case .ended:
            let options = optionRaw.map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            let shouldResume = options.contains(.shouldResume)
            nowPlayingSync.logNowPlayingEvent("interruption", trigger: "system", extra: "phase=ended shouldResume=\(shouldResume) wasPlaying=\(wasPlayingAtInterruption)")
            if wasPlayingAtInterruption && shouldResume {
                preparePlaybackAudioSession()
                playCurrentItem()
                isPlaying = true
                syncPlaybackChrome(liveTime: currentTime)
                syncPlaybackActivityFlag()
                if isInBackground {
                    startBackgroundPositionTracking()
                } else {
                    startPeriodicSave()
                }
                nowPlayingSync.updateNowPlaying()
                nowPlayingSync.scheduleNowPlayingReassert()
            } else if wasPlayingAtInterruption {
                // 割り込みが終わると、システムが playbackState を再生中へ戻すことがある。
                // 再開しないときは停止を書き直し、他アプリへセッションを返す。
                publishPausedNowPlaying(
                    elapsed: nil,
                    notifyOthersOnDeactivation: true,
                    releaseInBackground: true
                )
            }
            wasPlayingAtInterruption = false
        @unknown default:
            break
        }
    }

    // MARK: - App-kill Restoration

    /// アプリ強制終了・再起動後に最後に再生していたエピソードを一時停止状態で復元する。
    /// MiniPlayer にエピソードが表示され、ユーザーが再生ボタンをタップすると続きから再開できる。
    func restoreLastEpisodeIfNeeded(context: ModelContext) {
        guard currentEpisode == nil else { return }
        guard let audioURL = AppSettings.lastPlayingEpisodeAudioURL, !audioURL.isEmpty else { return }

        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { ep in ep.audioURL == audioURL }
        )
        guard let episode = (try? context.fetch(descriptor))?.first else {
            AppSettings.lastPlayingEpisodeAudioURL = nil
            return
        }

        // 再生済みで位置が 0 のエピソードは復元しない（続きがない）。
        guard !episode.isPlayed || episode.playbackPosition > 0 else {
            AppSettings.lastPlayingEpisodeAudioURL = nil
            return
        }

        modelContext = context
        playbackGeneration += 1
        let generation = playbackGeneration
        currentEpisode = episode
        currentTime = episode.playbackPosition
        duration = episode.totalDuration
        didReachPlaybackEnd = false

        guard let url = resolvePlaybackURL(for: episode) else {
            currentEpisode = nil
            return
        }

        let isBookmarkedLocal = episode.audioURL.hasPrefix("localfile://")
            || episode.audioURL.hasPrefix("localfolder://")

        if isBookmarkedLocal {
            Task { [weak self] in
                guard let self else { return }
                try? await BookmarkedFilePlaybackPreparer.ensurePlayable(at: url)
                guard self.playbackGeneration == generation, self.currentEpisode?.persistentModelID == episode.persistentModelID else { return }
                self.installRestoredPlayer(
                    url: url,
                    episode: episode,
                    isBookmarkedLocal: true,
                    generation: generation
                )
            }
            return
        }

        installRestoredPlayer(
            url: url,
            episode: episode,
            isBookmarkedLocal: false,
            generation: generation
        )
    }

    /// 新しい AVPlayer を作り、監視を付け、保存された位置へ移す（再生の開始と、前回の復元で共通）。
    /// ここに監視を足せば、どちらの経路にも効く。
    private func installPlayer(
        url: URL,
        episode: Episode,
        isBookmarkedLocal: Bool,
        generation: Int
    ) {
        let isLocalFile = url.isFileURL && !isBookmarkedLocal
        let item = makePlayerItem(url: url, isLocalFile: isLocalFile)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.allowsExternalPlayback = false
        // ストリーミングはバッファ待ちを有効にして切れ欠けノイズを抑える。ローカルは即時再生。
        newPlayer.automaticallyWaitsToMinimizeStalling = !isLocalFile
        player = newPlayer
        nowPlayingSync.attachPlayer(newPlayer)

        attachPeriodicTimeObserver(generation: generation)
        attachEndObserver(for: item, generation: generation)
        attachStalledObserver(for: item)
        attachTimeControlObserver()
        attachItemStatusObserver(for: item)

        Task { [weak self] in
            await self?.loadDurationFromAssetIfNeeded(generation: generation)
        }

        if episode.playbackPosition > 0 {
            // seek 完了前の周期サンプル（時刻 0）で表示を上書きしないよう、同じ経路で seek する。
            startTrackedSeek(to: episode.playbackPosition)
        }
    }

    private func installRestoredPlayer(
        url: URL,
        episode: Episode,
        isBookmarkedLocal: Bool,
        generation: Int
    ) {
        installPlayer(
            url: url,
            episode: episode,
            isBookmarkedLocal: isBookmarkedLocal,
            generation: generation
        )

        isPlaying = false
        syncPlaybackChrome(liveTime: currentTime)
        nowPlayingSync.syncRemoteCommandsAvailability()
        nowPlayingSync.refreshNowPlayingArtwork(for: episode)

        bgLog.info("✅ restored last episode: \(episode.title, privacy: .public) at \(episode.playbackPosition)s")
    }

}

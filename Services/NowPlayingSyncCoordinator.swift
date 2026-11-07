@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
import UIKit
import os.log

/// CS/LS（Control Center・ロック画面）表示ズレ調査用。truth（アプリ正）/ av（AVPlayer 実値）/
/// np（MPNowPlayingInfoCenter 書き込み値）の 1 行スナップショットをこのカテゴリにまとめる。
private let npLog = Logger(subsystem: "com.osamushikubo.osmPod", category: "NowPlaying")

/// `AudioPlayerService` から Now Playing（`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`）
/// 同期の責務を切り出したコーディネータ。`AudioPlayerService` が唯一のオーナーとして生成・保持し、
/// `init` の中で `owner` を自分自身に設定して使う（`AudioPlayerService.init` 内では `self` が
/// まだ使えないため、生成直後に弱参照を後付けする）。
///
/// CC / ロック画面は `MPNowPlayingSession`（iOS 16+）経由で管理する。AVAudioSession が
/// アクティブな限り「再生中」と自動推測して上書きしてしまう legacy な `.default()` /
/// `.shared()` の挙動を避け、現在の AVPlayer に紐付いた専用の nowPlayingInfoCenter /
/// remoteCommandCenter を使うことで、バックグラウンドのネットワーク切断時でも意図通りに
/// 一時停止表示へ補正できるようにしている（`infoCenter` / `commandCenter` 経由でアクセス）。
/// 正は `AudioPlayerService.isPlaying` のみ。CC / ロック画面は pausePlayback / resumePlayback の末尾で同期する。
@MainActor
final class NowPlayingSyncCoordinator {
    weak var owner: AudioPlayerService?

    private var nowPlayingArtworkURLString: String?
    private var nowPlayingArtworkImage: UIImage?
    private var nowPlayingArtworkTask: Task<Void, Never>?
    /// iOS が CC 操作後に playbackRate を 1.0 へ戻すことがあるため、短い遅延で再反映する。
    private var nowPlayingReassertTask: Task<Void, Never>?
    /// バックグラウンドでネットワークが切れて実際には無音でも、AVAudioSession がアクティブな限り
    /// iOS が「再生中」と自動推測して Control Center 側の表示を上書きしてしまう問題への対策。
    /// MPNowPlayingSession（iOS 16+）は特定の AVPlayer に紐付いた専用の nowPlayingInfoCenter /
    /// remoteCommandCenter を持ち、その自動推測から切り離して CC/LS の表示を直接制御できる。
    /// players 配列が空だと init 時にアサートするため、最初の AVPlayer ができるまで遅延生成する。
    /// 新しい AVPlayer が来るたび `attachPlayer` でセッションごと作り直す（理由は `attachPlayer` 参照）。
    private var nowPlayingSession: MPNowPlayingSession?

    private var infoCenter: MPNowPlayingInfoCenter {
        nowPlayingSession?.nowPlayingInfoCenter ?? MPNowPlayingInfoCenter.default()
    }
    private var commandCenter: MPRemoteCommandCenter {
        nowPlayingSession?.remoteCommandCenter ?? MPRemoteCommandCenter.shared()
    }

    /// 新しい AVPlayer ができるたび（`startPlayback` / `installRestoredPlayer`）に呼ぶ。
    ///
    /// 既存セッションの players を addPlayer/removePlayer で入れ替える方式は試したが、
    /// OS 側（nowplayingd）の内部登録状態と Swift 側の `session.players` がズレることがあり、
    /// ズレたまま removePlayer を呼ぶと「そのプレイヤーはobserverとして登録されていない」で
    /// 即アボートする（実機で発生確認済み。Swift の do/catch では捕まえられない ObjC 例外）。
    /// そのためプレイヤーが変わるたびセッションごと作り直す。古いセッションは参照を手放すだけで
    /// OS 側の解除は deinit に任せ、危険な removePlayer 呼び出し自体を避ける。
    func attachPlayer(_ player: AVPlayer) {
        let session = MPNowPlayingSession(players: [player])
        // true のままだと nowPlayingInfoCenter を手動で使えない（AVPlayerItem 側の
        // nowPlayingInfo に頼る自動公開になり、rate/playbackState を独自ロジックで
        // 補正できなくなる）ため、必ず手動管理にする。
        session.automaticallyPublishesNowPlayingInfo = false
        nowPlayingSession = session
        // セッションを作り直すたびリモートコマンドのターゲットも新しい commandCenter に
        // 登録し直す必要がある（前のセッションの commandCenter は解放されて無効になる）。
        setupRemoteCommands()
        nowPlayingSession?.becomeActiveIfPossible { [weak self] isActive in
            guard let self else { return }
            Task { @MainActor in
                self.logNowPlayingEvent("nowPlayingSession", trigger: "internal", extra: "becomeActive=\(isActive)")
                // 非アクティブ中の nowPlayingInfo はコントロールセンターに届かない。
                // セッションが聴き始めた瞬間に、そのときの isPlaying を書き直す。
                guard isActive else { return }
                self.applyNowPlayingInfo()
            }
        }
    }

    // MARK: - CS/LS 表示ズレ調査用ログ
    //
    // truth（アプリ正 = isPlaying）/ av（AVPlayer 実値）/ np（MPNowPlayingInfoCenter へ
    // 書いた／読んだ値）の 3 者が一致しているかを、イベントが起きるたびに 1 行へまとめて残す。
    // 再現時にこのログだけを見れば「誰が・いつ・どれをズラしたか」を追えることを狙う。

    /// truth / av / np の 1 行スナップショット。
    private func nowPlayingLogLine(event: String, trigger: String, extra: String = "") -> String {
        guard let owner else {
            return "event=\(event) trigger=\(trigger) truth=unknown (AudioPlayerService deallocated)"
        }
        let player = owner.player
        let avRate = player?.rate ?? -1
        let avTimeControl: String
        switch player?.timeControlStatus {
        case .some(.playing): avTimeControl = "playing"
        case .some(.paused): avTimeControl = "paused"
        case .some(.waitingToPlayAtSpecifiedRate):
            avTimeControl = "waiting(\(player?.reasonForWaitingToPlay?.rawValue ?? "?"))"
        case .none: avTimeControl = "nil"
        @unknown default: avTimeControl = "unknown"
        }
        let npInfo = infoCenter.nowPlayingInfo
        let npRate = (npInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue
        let npElapsed = (npInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue
        let center = commandCenter
        let episodeID = owner.currentEpisode.map { String($0.audioURL.suffix(10)) } ?? "nil"
        let itemStatus: String
        switch player?.currentItem?.status {
        case .some(.unknown): itemStatus = "unknown"
        case .some(.readyToPlay): itemStatus = "readyToPlay"
        case .some(.failed): itemStatus = "failed(\(player?.currentItem?.error?.localizedDescription ?? "?"))"
        case .none: itemStatus = "nil"
        @unknown default: itemStatus = "unknown"
        }

        var line = "event=\(event) trigger=\(trigger)"
        line += " truth.isPlaying=\(owner.isPlaying) truth.isNetworkStalled=\(owner.isNetworkStalled)"
        line += " av.rate=\(avRate) av.timeControl=\(avTimeControl) av.itemStatus=\(itemStatus)"
        line += " np.rate=\(npRate.map { String($0) } ?? "nil")"
        line += " np.playbackState=\(infoCenter.playbackState) np.sessionActive=\(nowPlayingSession?.isActive ?? false)"
        line += " np.elapsed=\(npElapsed.map { String(format: "%.1f", $0) } ?? "nil")"
        line += " np.hasInfo=\(npInfo != nil)"
        line += " remote.playEnabled=\(center.playCommand.isEnabled) remote.pauseEnabled=\(center.pauseCommand.isEnabled)"
        line += " scene=\(owner.isInBackground ? "background" : "foreground")"
        line += " episodeID=\(episodeID)"
        if !extra.isEmpty { line += " \(extra)" }
        return line
    }

    /// 通常ログ（開発者モード ON のときだけ出す。OFF 時は過剰ログを避ける）。
    func logNowPlayingEvent(_ event: String, trigger: String, extra: String = "") {
        guard AppSettings.developerModeEnabled else { return }
        npLog.info("\(self.nowPlayingLogLine(event: event, trigger: trigger, extra: extra), privacy: .public)")
    }

    /// truth / av / np の不一致を明示する WARNING。再現調査の起点になるため、
    /// 開発者モードの ON/OFF に関わらず常に残す。
    func warnNowPlayingMismatch(_ reason: String, event: String, trigger: String) {
        npLog.warning("⚠️ mismatch(\(reason, privacy: .public)): \(self.nowPlayingLogLine(event: event, trigger: trigger), privacy: .public)")
    }

    // MARK: - Now Playing

    func clearNowPlaying() {
        nowPlayingReassertTask?.cancel()
        nowPlayingReassertTask = nil
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
        syncRemoteCommandsAvailability()
    }

    /// `AudioPlayerService.teardownPlayer()` から呼ぶ。アートワーク読み込みも含めて全タスクを止める。
    /// ここではセッションからプレイヤーを外さない（次のエピソードへ続けて再生する場合、
    /// 直後の `attachPlayer` が新プレイヤー追加→旧プレイヤー削除の順で入れ替えるため、
    /// ここで先に外すと players が一瞬空になりフリーズ・クラッシュの原因になる。
    /// 完全に再生が止まって次の attachPlayer が来ない場合でも、古いプレイヤーが
    /// 1つ残るだけで実害はない）。
    func teardown() {
        cancelArtworkLoading()
        clearNowPlaying()
    }

    /// バックグラウンド移行時など、Now Playing 自体はそのままにアートワーク読み込みだけ止めたいときに使う。
    func cancelArtworkLoading() {
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
    }

    private func resolvedElapsedForNowPlaying() -> TimeInterval {
        guard let owner else { return 0 }
        if let player = owner.player {
            let raw = player.currentTime().seconds
            if raw.isFinite, raw >= 0 {
                if owner.isInBackground, owner.isPlaying {
                    owner.inMemoryPlaybackPosition = raw
                }
                return raw
            }
        }
        return owner.isInBackground ? owner.inMemoryPlaybackPosition : owner.currentTime
    }

    private func playbackRateForNowPlaying() -> Double {
        guard let owner else { return 0 }
        return (owner.didReachPlaybackEnd || !owner.isPlaying || owner.isNetworkStalled) ? 0 : 1
    }

    /// CC / ロック画面へ `isPlaying` を書き込む。
    func applyNowPlayingInfo(elapsed: TimeInterval? = nil) {
        guard let owner, owner.currentEpisode != nil else {
            clearNowPlaying()
            return
        }

        let resolvedElapsed = elapsed ?? resolvedElapsedForNowPlaying()
        let rate = playbackRateForNowPlaying()
        // CC は PlaybackRate が 0 でも、DefaultPlaybackRate や AVPlayer.defaultRate が
        // 1 のままだと再生中とみなして ⏸ に戻す。止まっているあいだは両方 0 にする。
        owner.player?.defaultRate = rate > 0 ? 1 : 0

        var info = buildNowPlayingMetadataDictionary()
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: resolvedElapsed)
        info[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: rate)
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = NSNumber(value: rate > 0 ? 1.0 : 0.0)

        let state: MPNowPlayingPlaybackState = rate > 0 ? .playing : .paused
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = state
        suppressStaleDefaultNowPlayingCenter(publishedRate: rate)
        // nowPlayingInfo の代入が playbackState を非同期で再生中へ戻すことがある。
        // 同じ値をもう一度、次のターンで書き直してその上書きに勝つ。
        let publishedRate = rate
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.playbackRateForNowPlaying() == publishedRate else { return }
            self.infoCenter.playbackState = state
        }
        logNowPlayingEvent("applyNowPlaying", trigger: "internal", extra: "wroteRate=\(rate) wroteElapsed=\(String(format: "%.1f", resolvedElapsed))")
    }

    /// セッション経由で書いているあいだ、`.default()` に残ったレートで
    /// コントロールセンターが ⏸ に戻らないように、同じ再生状態を重ねて書く。
    private func suppressStaleDefaultNowPlayingCenter(publishedRate: Double) {
        guard nowPlayingSession != nil else { return }
        let shared = MPNowPlayingInfoCenter.default()
        guard shared !== infoCenter else { return }
        if var info = shared.nowPlayingInfo {
            info[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: publishedRate)
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = NSNumber(value: publishedRate > 0 ? 1.0 : 0.0)
            shared.nowPlayingInfo = info
        }
        shared.playbackState = publishedRate > 0 ? .playing : .paused
    }

    /// メタデータ更新（アートワーク・duration 等）向け。
    func updateNowPlaying(elapsed: TimeInterval? = nil) {
        applyNowPlayingInfo(elapsed: elapsed)
    }

    /// AVPlayer の自動 NowPlayingInfo 更新が rate を上書きすることがある。
    /// 1 回だけでは負けるため、複数のタイミングで繰り返し再反映する。
    func scheduleNowPlayingReassert(elapsed: TimeInterval? = nil) {
        nowPlayingReassertTask?.cancel()
        let expectedPlaying = owner?.isPlaying ?? false
        logNowPlayingEvent("reassert", trigger: "internal", extra: "phase=start expectedPlaying=\(expectedPlaying)")
        nowPlayingReassertTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if expectedPlaying {
                // CC の再生/一時停止ボタンは PlaybackRate の「値」ではなく「変化(エッジ)」に
                // 反応して再描画される場合がある。同じ rate=1 を書き直すだけでは、既に描画が
                // ずれてしまった CC のボタンが直らないことがあるため、再開直後に一度だけ
                // 0→1 のエッジを強制発生させ、確実に再同期させる。
                await self.forceNowPlayingRateEdge(elapsed: elapsed, expectedPlaying: expectedPlaying)
            }
            for ms in [80, 200, 400, 800] as [Int] {
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled else {
                    self.logNowPlayingEvent("reassert", trigger: "internal", extra: "phase=stopped reason=cancelled")
                    return
                }
                guard let owner = self.owner, owner.isPlaying == expectedPlaying else {
                    self.logNowPlayingEvent("reassert", trigger: "internal", extra: "phase=stopped reason=stateChanged expectedPlaying=\(expectedPlaying) nowIsPlaying=\(self.owner?.isPlaying ?? false)")
                    return
                }
                // isPlaying=false の間に AVPlayer が再び rate>0 へ戻ろうとした場合、表示だけでなく
                // 実際の再生も毎回止め直す（pause() 一回では戻ってしまうことがあるため）。
                if !expectedPlaying, (owner.player?.rate ?? 0) > 0 {
                    self.warnNowPlayingMismatch("truth=paused,av.rate>0 during reassert", event: "reassert", trigger: "internal")
                    owner.player?.pause()
                    owner.player?.rate = 0
                }
                self.applyNowPlayingInfo(elapsed: elapsed)
            }
            guard !Task.isCancelled else {
                self.logNowPlayingEvent("reassert", trigger: "internal", extra: "phase=stopped reason=cancelled")
                return
            }
            guard let owner = self.owner, owner.isPlaying == expectedPlaying else {
                self.logNowPlayingEvent("reassert", trigger: "internal", extra: "phase=stopped reason=stateChanged expectedPlaying=\(expectedPlaying) nowIsPlaying=\(self.owner?.isPlaying ?? false)")
                return
            }
            self.syncRemoteCommandsAvailability()
            self.logNowPlayingEvent("reassert", trigger: "internal", extra: "phase=completed")
        }
    }

    /// `nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate]` に意図的な 0→1 のエッジを
    /// 発生させ、CC の再生ボタンの再描画を強制する。呼び出し元は `expectedPlaying` の間だけ
    /// 有効なので、待機中に状態が変わっていたら何もしない。
    func forceNowPlayingRateEdge(elapsed: TimeInterval?, expectedPlaying: Bool) async {
        guard let owner, owner.currentEpisode != nil else { return }
        var info = infoCenter.nowPlayingInfo ?? buildNowPlayingMetadataDictionary()
        info[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: 0.0)
        infoCenter.nowPlayingInfo = info
        logNowPlayingEvent("rateEdge", trigger: "internal", extra: "phase=zero expectedPlaying=\(expectedPlaying)")
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled, self.owner?.isPlaying == expectedPlaying else {
            // ここで何もせず抜けると nowPlayingInfo が rate=0 のまま取り残され、実際は再生中なのに
            // CC/ロック画面が ▶︎（停止扱い）のまま固まる「パターン2」を引き起こす
            // （このタスクが別の scheduleNowPlayingReassert 呼び出しにキャンセルされた場合など）。
            // truth（isPlaying）が再生中である限り、このタスク自体がキャンセルされていても
            // 同期的な nowPlayingInfo 書き込みは問題なく効くので、必ず正しい値へ復元してから抜ける。
            if self.owner?.isPlaying == true {
                warnNowPlayingMismatch(
                    "rateEdge aborted (cancelled=\(Task.isCancelled)) while truth=playing — restoring np immediately",
                    event: "rateEdge", trigger: "internal"
                )
                applyNowPlayingInfo(elapsed: elapsed)
            } else {
                logNowPlayingEvent("rateEdge", trigger: "internal", extra: "phase=abort cancelled=\(Task.isCancelled) isPlayingNow=\(self.owner?.isPlaying ?? false)")
            }
            return
        }
        applyNowPlayingInfo(elapsed: elapsed)
        logNowPlayingEvent("rateEdge", trigger: "internal", extra: "phase=restored")
    }

    /// play/pause は常に有効（`isPlaying` で切ると CC / ロック画面の ▶︎ が薄くなる）。
    func syncRemoteCommandsAvailability() {
        guard let owner else { return }
        let center = commandCenter
        let active = owner.currentEpisode != nil && !owner.didReachPlaybackEnd
        center.playCommand.isEnabled = active
        center.pauseCommand.isEnabled = active
        center.skipForwardCommand.isEnabled = active
        center.skipBackwardCommand.isEnabled = active
        center.changePlaybackPositionCommand.isEnabled = active
    }

    private func buildNowPlayingMetadataDictionary() -> [String: Any] {
        guard let owner, let ep = owner.currentEpisode else { return [:] }
        let title = ep.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = ep.show.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? "—" : title,
            MPMediaItemPropertyArtist: artist.isEmpty ? "osmPod" : artist,
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue),
        ]
        if owner.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = owner.duration
        }
        let artworkImage = nowPlayingArtworkImage ?? Self.fallbackNowPlayingArtwork
        info[MPMediaItemPropertyArtwork] = makeMPMediaItemArtwork(
            image: artworkImage,
            boundsSize: CGSize(width: 600, height: 600)
        )
        return info
    }

    func refreshNowPlayingArtwork(for episode: Episode) {
        let artworkURL = resolvedArtworkURL(for: episode)
        let artworkKey = artworkURL?.absoluteString

        if nowPlayingArtworkURLString == artworkKey, nowPlayingArtworkImage != nil {
            updateNowPlaying()
            return
        }

        if nowPlayingArtworkURLString != artworkKey {
            nowPlayingArtworkImage = nil
        }
        nowPlayingArtworkURLString = artworkKey
        nowPlayingArtworkTask?.cancel()
        updateNowPlaying()

        guard let artworkURL else { return }

        nowPlayingArtworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let data = await ThumbnailImageCache.shared.data(for: artworkURL)
            guard !Task.isCancelled else { return }
            guard self.nowPlayingArtworkURLString == artworkKey else { return }
            if let data, let image = UIImage(data: data) {
                self.nowPlayingArtworkImage = image
            }
            self.updateNowPlaying()
        }
    }

    private static let fallbackNowPlayingArtwork: UIImage = {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.secondarySystemFill.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 200, weight: .regular)
            let symbol = UIImage(systemName: "waveform.circle.fill", withConfiguration: config)
            symbol?.draw(in: CGRect(x: 150, y: 150, width: 300, height: 300))
        }
    }()

    private func resolvedArtworkURL(for episode: Episode) -> URL? {
        let raw = episode.artworkURL ?? episode.show.artworkURL
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        guard var components = URLComponents(string: trimmed) else {
            return URL(string: trimmed)
        }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url ?? URL(string: trimmed)
    }

    nonisolated private func performRemoteCommand(_ action: @MainActor () -> MPRemoteCommandHandlerStatus) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(action)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(action)
        }
    }

    private func setupRemoteCommands() {
        let center = commandCenter
        center.togglePlayPauseCommand.isEnabled = false

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performRemoteCommand {
                guard let owner = self.owner else { return .commandFailed }
                self.logNowPlayingEvent("remote.play", trigger: "remote", extra: "phase=received")
                owner.resumePlayback(trigger: "remote")
                return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performRemoteCommand {
                guard let owner = self.owner else { return .commandFailed }
                self.logNowPlayingEvent("remote.pause", trigger: "remote", extra: "phase=received")
                if owner.isPlaying {
                    owner.pausePlayback(trigger: "remote")
                } else {
                    // 割り込みがすでに止めていた場合など: 手動停止の意図を記録して自動再開を抑制し、
                    // NowPlayingInfo を再同期 + セッション非アクティブで playbackState をリセットする
                    owner.wasPlayingAtInterruption = false
                    self.applyNowPlayingInfo()
                    self.syncRemoteCommandsAvailability()
                    owner.releasePlaybackAudioSessionFromRemotePause()
                    self.logNowPlayingEvent("remote.pause", trigger: "remote", extra: "phase=alreadyPaused")
                }
                return .success
            }
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self, let owner = self.owner else { return .commandFailed }
            return self.performRemoteCommand {
                guard owner.currentEpisode != nil else { return .commandFailed }
                owner.seekForward()
                return .success
            }
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self, let owner = self.owner else { return .commandFailed }
            return self.performRemoteCommand {
                guard owner.currentEpisode != nil else { return .commandFailed }
                owner.seekBackward()
                return .success
            }
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let owner = self.owner,
                  let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self.performRemoteCommand {
                guard owner.currentEpisode != nil else { return .commandFailed }
                owner.seek(to: e.positionTime)
                return .success
            }
        }

        syncRemoteCommandsAvailability()
    }
}

// MARK: - Now Playing アートワーク（MediaPlayer 専用キュー対応）

/// `MPMediaItemArtwork` の `requestHandler` は Main Actor 外・別ディスパッチキューで呼ばれる。
/// `@MainActor` 型のメソッド内で `{ … }` を渡すとクロージャに actor 隔離が付き、実行時にクラッシュするため、
/// ファイルスコープの非隔離関数で `@Sendable` ハンドラのみを構築する。
private func makeMPMediaItemArtwork(image: UIImage, boundsSize: CGSize) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: boundsSize) { @Sendable _ in
        image
    }
}

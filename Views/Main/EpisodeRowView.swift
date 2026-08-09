import SwiftUI
import SwiftData

struct EpisodeRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackChromeState.self) private var playbackChrome
    @Environment(EpisodeDownloadService.self) private var downloadService
    @Environment(LanguageSettings.self) private var lang

    @AppStorage("dateFormat") private var dateFormatRaw: String = DateFormat.yyyyMMdd.rawValue

    let episode: Episode
    /// ライブラリ一覧のエピソード行では `false`（サムネ読み込みを避け、左揃えを揃える）。
    var showsArtwork: Bool = false
    /// `true` の場合、常にクリーム色の `AppPalette.cardFill` 上に置かれる前提で固定の文字色を使う
    /// （フォルダカード内での使用）。`false` は `.primary`/`.secondary` のまま
    /// システム標準背景（検索結果など）に追従させる。
    var isOnCard: Bool = false
    var onTap: (() -> Void)? = nil

    private var dateFormat: DateFormat { DateFormat(rawValue: dateFormatRaw) ?? .yyyyMMdd }
    private let newEpisodeIndicatorColor = Color(red: 0.67, green: 0.9, blue: 0.25)

    private var primaryTextStyle: AnyShapeStyle {
        isOnCard ? AnyShapeStyle(AppPalette.textOnCardPrimary) : AnyShapeStyle(.primary)
    }

    private var secondaryTextStyle: AnyShapeStyle {
        isOnCard ? AnyShapeStyle(AppPalette.textOnCardSecondary) : AnyShapeStyle(.secondary)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                HapticManager.shared.provideFeedback()
                markAsSeenIfNeeded()
                onTap?()
            } label: {
                Group {
                    if showsArtwork {
                        HStack(alignment: .center, spacing: 12) {
                            ThumbnailArtworkView(
                                artworkURLString: episode.show.artworkURL,
                                placeholderSystemImage: "waveform"
                            )
                            episodeTextColumn
                        }
                    } else {
                        episodeTextColumn
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    HapticManager.shared.provideFeedback()
                    toggleFavorite()
                } label: {
                    Image(systemName: episode.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(
                            episode.isFavorite
                                ? AnyShapeStyle(.yellow)
                                : secondaryTextStyle
                        )
                }
                .buttonStyle(.plain)

                VStack(spacing: 4) {
                    Button {
                        HapticManager.shared.provideFeedback()
                        Task {
                            try? await downloadService.toggleDownload(for: episode, context: modelContext)
                        }
                    } label: {
                        if downloadService.isDownloading(episode) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: downloadService.isDownloaded(episode) ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(
                                    downloadService.isDownloaded(episode)
                                        ? AnyShapeStyle(.green)
                                        : secondaryTextStyle
                                )
                        }
                    }
                    .buttonStyle(.plain)

                    if episode.isPlayed {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                    } else if displayedPlaybackPosition > 0 {
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                    } else {
                        Color.clear.frame(width: 8, height: 8)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private var episodeTextColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if episode.isNew {
                    Circle()
                        .fill(newEpisodeIndicatorColor)
                        .frame(width: 8, height: 8)
                }

                Text(episodeTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(
                        isCurrentlyPlaying
                            ? AnyShapeStyle(.tint)
                            : primaryTextStyle
                    )
                    .multilineTextAlignment(.leading)
                    .episodePlayedStateLongPress(episode: episode)
            }

            episodeMetadataRow
        }
    }

    /// 再生時間ラベルが伸びても日付行の高さが変わらないよう、最長表示分の幅を確保する。
    private static let widestPlaybackLabel = "9:59:59 / 9:59:59"

    private var episodeMetadataRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if let publishedAt = episode.publishedAt {
                    Text(publishedAt.compactDisplayString(format: dateFormat))
                } else {
                    Text(lang.strings.noPublishDate)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            if let label = playbackLabel {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .background(alignment: .leading) {
                        Text(Self.widestPlaybackLabel)
                            .font(.caption.monospacedDigit())
                            .hidden()
                    }
            }
        }
        .font(.caption)
        .foregroundStyle(secondaryTextStyle)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var isCurrentlyPlaying: Bool {
        guard playbackChrome.isPlaying,
              let id = playbackChrome.nowPlayingEpisodeID else { return false }
        return id == episode.persistentModelID
    }

    private var episodeTitle: String {
        if let number = episode.number {
            return "#\(number) \(episode.title)"
        }
        return episode.title
    }

    /// 再生中行だけ低頻度の `liveDisplayTime` を使い、それ以外は保存済み位置。
    private var displayedPlaybackPosition: TimeInterval {
        if isCurrentlyPlaying { return playbackChrome.liveDisplayTime }
        return episode.playbackPosition
    }

    private var playbackLabel: String? {
        let pos = displayedPlaybackPosition
        let total = episode.totalDuration
        guard pos > 0 || total > 0 else { return nil }
        if total > 0 {
            return "\(formatTime(pos)) / \(formatTime(total))"
        }
        return formatTime(pos)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    @MainActor
    private func markAsSeenIfNeeded() {
        episode.clearNewIndicator()
        try? modelContext.save()
    }

    @MainActor
    private func toggleFavorite() {
        episode.isFavorite.toggle()

        if episode.isFavorite {
            let favoriteFolder = FavoriteFolderService.ensureFavoriteRootFolder(context: modelContext)
            if !episode.groups.contains(where: { $0.persistentModelID == favoriteFolder.persistentModelID }) {
                episode.groups.append(favoriteFolder)
            }
            if !favoriteFolder.episodes.contains(where: { $0.persistentModelID == episode.persistentModelID }) {
                favoriteFolder.episodes.append(episode)
            }
        } else {
            let favoriteFolder = FavoriteFolderService.ensureFavoriteRootFolder(context: modelContext)
            episode.groups.removeAll { $0.persistentModelID == favoriteFolder.persistentModelID }
            favoriteFolder.episodes.removeAll { $0.persistentModelID == episode.persistentModelID }
        }

        try? modelContext.save()
    }
}

// MARK: - 再生済み／未再生の長押しメニュー

struct EpisodePlayedStateLongPressModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LanguageSettings.self) private var lang

    let episode: Episode
    @State private var showPlayedStateDialog = false

    func body(content: Content) -> some View {
        let s = lang.strings
        content
            .onLongPressGesture {
                HapticManager.shared.provideFeedback()
                showPlayedStateDialog = true
            }
            .confirmationDialog(
                s.playbackState,
                isPresented: $showPlayedStateDialog,
                titleVisibility: .visible
            ) {
                Button(s.markAsPlayed) {
                    markAsPlayed()
                }
                Button(s.markAsUnplayed) {
                    markAsUnplayed()
                }
                Button(s.cancel, role: .cancel) {}
            }
    }

    @MainActor
    private func markAsPlayed() {
        episode.markAsPlayedManually()
        try? modelContext.save()
    }

    @MainActor
    private func markAsUnplayed() {
        episode.markAsUnplayedManually()
        if audioPlayer.currentEpisode?.persistentModelID == episode.persistentModelID {
            audioPlayer.seek(to: 0)
        }
        try? modelContext.save()
    }
}

extension View {
    func episodePlayedStateLongPress(episode: Episode) -> some View {
        modifier(EpisodePlayedStateLongPressModifier(episode: episode))
    }
}

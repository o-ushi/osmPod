import SwiftUI
import SwiftData

struct PlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(EpisodeDownloadService.self) private var downloadService
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageSettings.self) private var lang

    /// ドラッグ中はタイマーによる currentTime の上書きをブロックするためのフラグ。
    @State private var isDraggingSlider = false
    /// ドラッグ中にスライダーが表示する値（指を離したときに seek する）。
    @State private var sliderDragValue: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    playerArtworkView
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text(audioPlayer.currentEpisode?.title ?? "")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(audioPlayer.currentEpisode?.show.title ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)

                    if let episode = audioPlayer.currentEpisode {
                        HStack(spacing: 24) {
                            Button {
                                HapticManager.shared.provideFeedback()
                                audioPlayer.toggleRepeat()
                            } label: {
                                Label(
                                    lang.strings.repeatPlayback,
                                    systemImage: audioPlayer.isRepeatEnabled ? "repeat.1" : "repeat"
                                )
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .foregroundStyle(
                                    audioPlayer.isRepeatEnabled
                                        ? AnyShapeStyle(.tint)
                                        : AnyShapeStyle(.secondary)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                HapticManager.shared.provideFeedback()
                                toggleFavorite(episode: episode)
                            } label: {
                                Label(
                                    episode.isFavorite ? lang.strings.favorited : lang.strings.favorite,
                                    systemImage: episode.isFavorite ? "star.fill" : "star"
                                )
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .foregroundStyle(
                                    episode.isFavorite
                                        ? AnyShapeStyle(.yellow)
                                        : AnyShapeStyle(.secondary)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                HapticManager.shared.provideFeedback()
                                Task {
                                    try? await downloadService.toggleDownload(for: episode, context: modelContext)
                                }
                            } label: {
                                if downloadService.isDownloading(episode) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 20, height: 20)
                                } else {
                                    Label(
                                        downloadService.isDownloaded(episode) ? lang.strings.downloaded : lang.strings.download,
                                        systemImage: downloadService.isDownloaded(episode) ? "checkmark.circle.fill" : "arrow.down.circle"
                                    )
                                    .labelStyle(.iconOnly)
                                    .font(.title2)
                                    .foregroundStyle(
                                        downloadService.isDownloaded(episode)
                                            ? AnyShapeStyle(.green)
                                            : AnyShapeStyle(.secondary)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { isDraggingSlider ? sliderDragValue : audioPlayer.currentTime },
                                set: { newValue in
                                    // set は onEditingChanged(true) より先に呼ばれることがあるため
                                    // ここでもドラッグ開始を検知してフラグを立てる。
                                    if !isDraggingSlider {
                                        sliderDragValue = audioPlayer.currentTime
                                        isDraggingSlider = true
                                    }
                                    sliderDragValue = newValue
                                }
                            ),
                            in: 0...max(audioPlayer.duration, 1),
                            onEditingChanged: { editing in
                                if !editing {
                                    isDraggingSlider = false
                                    audioPlayer.seek(to: sliderDragValue)
                                }
                            }
                        )
                        HStack {
                            Text(formatTime(isDraggingSlider ? sliderDragValue : audioPlayer.currentTime))
                            Spacer()
                            Text(formatTime(audioPlayer.duration))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // 再生中なのに通信が来ず音が出ていないとき。
                        if audioPlayer.isWaitingForConnection {
                            Label(lang.strings.waitingForConnection, systemImage: "wifi.exclamationmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                                .accessibilityIdentifier("waiting-for-connection")
                        }
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 36) {
                        Button {
                            HapticManager.shared.provideFeedback()
                            audioPlayer.seekBackward()
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                        }

                        Button {
                            HapticManager.shared.provideFeedback()
                            audioPlayer.togglePlayPause()
                        } label: {
                            Group {
                                if audioPlayer.cloudFilePreparation.isActive {
                                    ProgressView()
                                        .controlSize(.large)
                                } else {
                                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 68))
                                }
                            }
                            .frame(width: 68, height: 68)
                        }
                        .disabled(audioPlayer.cloudFilePreparation.isActive)

                        Button {
                            HapticManager.shared.provideFeedback()
                            audioPlayer.seekForward()
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.title)
                        }

                        Button {
                            HapticManager.shared.provideFeedback()
                            audioPlayer.skipToNextEpisode()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel(lang.strings.skipToNextEpisode)
                    }
                    .foregroundStyle(.primary)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang.strings.close) { dismiss() }
                }
                .osmPlainBackground()
            }
            .overlay {
                CloudFilePreparationOverlay()
            }
        }
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

    private var playerArtworkView: some View {
        Group {
            if let artworkURL = currentArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        artworkPlaceholder
                    @unknown default:
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 320, height: 320)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }

    private var currentArtworkURL: URL? {
        let raw = audioPlayer.currentEpisode?.artworkURL ?? audioPlayer.currentEpisode?.show.artworkURL
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

    private var artworkPlaceholder: some View {
        ZStack {
            Color(.secondarySystemFill)
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func toggleFavorite(episode: Episode) {
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

struct MiniPlayerView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LanguageSettings.self) private var lang
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.provideFeedback()
                onTap()
            } label: {
                HStack(spacing: 10) {
                    ThumbnailArtworkView(
                        artworkURLString: audioPlayer.currentEpisode?.artworkURL ?? audioPlayer.currentEpisode?.show.artworkURL,
                        placeholderSystemImage: "waveform",
                        cornerRadius: 8
                    )
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentEpisode?.title ?? "")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if audioPlayer.isWaitingForConnection {
                            // 番組名の代わりに、通信を待っていて音が出ていないことを出す。
                            Label(lang.strings.waitingForConnectionShort, systemImage: "wifi.exclamationmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        } else {
                            Text(audioPlayer.currentEpisode?.show.title ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                HapticManager.shared.provideFeedback()
                audioPlayer.seekBackward()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
            }

            Button {
                HapticManager.shared.provideFeedback()
                audioPlayer.togglePlayPause()
            } label: {
                Group {
                    if audioPlayer.cloudFilePreparation.isActive {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .disabled(audioPlayer.cloudFilePreparation.isActive)

            Button {
                HapticManager.shared.provideFeedback()
                audioPlayer.seekForward()
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

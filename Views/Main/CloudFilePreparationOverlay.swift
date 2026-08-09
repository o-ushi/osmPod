import SwiftUI

/// Dropbox 等のクラウドファイル取得中に、固まったように見えないよう進捗を表示する。
struct CloudFilePreparationOverlay: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LanguageSettings.self) private var lang

    var body: some View {
        @Bindable var prep = audioPlayer.cloudFilePreparation
        if prep.isActive {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Text(lang.strings.cloudFilePreparingTitle)
                        .font(.headline)

                    Text(prep.fileName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if prep.phase == .startingPlayback {
                        ProgressView()
                        Text(lang.strings.cloudFilePreparingStartingPlayback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let progress = prep.progress, let percent = prep.progressPercent {
                        ProgressView(value: progress)
                        Text(lang.strings.cloudFilePreparingPercent(percent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text(lang.strings.cloudFilePreparingIndeterminate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(lang.strings.cloudFilePreparingMessage)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(lang.strings.cloudFilePreparingTitle)
                .accessibilityValue(cloudFilePreparationAccessibilityValue(prep: prep, strings: lang.strings))
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: prep.isActive)
        }
    }

    private func cloudFilePreparationAccessibilityValue(
        prep: CloudFilePreparationState,
        strings: LocalizedStrings
    ) -> String {
        if prep.phase == .startingPlayback {
            return "\(prep.fileName), \(strings.cloudFilePreparingStartingPlayback)"
        }
        if let percent = prep.progressPercent {
            return "\(prep.fileName), \(strings.cloudFilePreparingPercent(percent))"
        }
        return "\(prep.fileName), \(strings.cloudFilePreparingIndeterminate)"
    }
}

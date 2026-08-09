import SwiftUI
import UIKit

/// osmStroll の `HelpView` と同様の `List` ベースのヘルプ。プランに応じて `AppImage` / `AppImageFree` を表示。
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return String(format: lang.strings.helpVersionFormat, v, b)
    }

    var body: some View {
        let s = lang.strings
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .center, spacing: 18) {
                        helpHeaderAppIconView
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.appTitle)
                                .font(.title.weight(.bold))
                                .foregroundStyle(AppPalette.textOnSubpagePrimary)
                            Text(appVersion)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppPalette.textOnSubpageSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Text(s.helpIntro)
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppPalette.textOnSubpagePrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                }

                Section {
                    helpRow(icon: "magnifyingglass.circle.fill", color: .green, title: s.helpAddShowSearchTitle, body: s.helpAddShowSearchBody)
                    helpRow(icon: "link.circle.fill", color: .teal, title: s.helpAddShowRSSTitle, body: s.helpAddShowRSSBody)
                    helpRow(icon: "sparkles", color: .indigo, title: s.helpAddShowAITitle, body: s.helpAddShowAIBody)
                } header: {
                    Text(s.helpSectionAddShow)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                Section {
                    helpRow(icon: "folder.fill", color: .blue, title: s.helpLibraryFoldersTitle, body: s.helpLibraryFoldersBody)
                    helpRow(icon: "arrow.up.arrow.down.circle.fill", color: .purple, title: s.helpLibrarySortTitle, body: s.helpLibrarySortBody)
                } header: {
                    Text(s.helpSectionLibrary)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                Section {
                    helpRow(icon: "magnifyingglass.circle.fill", color: .gray, title: s.helpSearchInstantTitle, body: s.helpSearchInstantBody)
                } header: {
                    Text(s.helpSectionSearch)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                Section {
                    helpRow(icon: "square.and.arrow.up.on.square.fill", color: .indigo, title: s.helpDataJsonTitle, body: s.helpDataJsonBody)
                } header: {
                    Text(s.helpSectionData)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                Section {
                    helpRow(icon: "play.circle.fill", color: .pink, title: s.helpPlaybackMiniTitle, body: s.helpPlaybackMiniBody)
                    helpRow(icon: "shuffle", color: .mint, title: s.helpPlaybackRandomTitle, body: s.helpPlaybackRandomBody)
                    helpRow(icon: "iphone.radiowaves.left.and.right", color: .orange, title: s.helpPlaybackShakeTitle, body: s.helpPlaybackShakeBody)
                } header: {
                    Text(s.helpSectionPlayback)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                Section {
                    helpRow(icon: "crown.fill", color: .orange, title: s.helpPlanIconTitle, body: s.helpPlanIconBody)
                } header: {
                    Text(s.helpSectionPlan)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label(PrivacyText.title(lang.language), systemImage: "hand.raised.fill")
                    }
                } footer: {
                    Text(PrivacyText.linkFooter(lang.language))
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()
            }
            .listStyle(.insetGrouped)
            .headerProminence(.increased)
            .osmSubpageListChrome()
            .navigationTitle(s.help)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(s.close)
                }
            }
        }
    }

    /// `PlanManagementView` のプラン別アプリ画像と同じ解決順。
    @ViewBuilder
    private var helpHeaderAppIconView: some View {
        let imageName = planStore.isFree ? "AppImageFree" : "AppImage"
        if let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: planStore.isFree
                                ? [.gray, .gray.opacity(0.7)]
                                : [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: planStore.isFree ? "dot.radiowaves.left.and.right" : "crown.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
            }
        }
    }

    private func helpRow(icon: String, color: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }
            Text(body)
                .font(.body.weight(.medium))
                .foregroundStyle(AppPalette.textOnCardSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    HelpView()
        .environment(LanguageSettings())
        .environment(PlanStore.shared)
}

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
                    OsmDisclosureRow(title: s.helpTAddTitle, systemImage: "magnifyingglass", accent: .orange) {
                        OsmStepList(steps: [s.helpTAdd1, s.helpTAdd2, s.helpTAdd3], accent: .orange)
                    }
                    OsmDisclosureRow(title: s.helpTRssTitle, systemImage: "link", accent: .orange) {
                        OsmStepList(steps: [s.helpTRss1, s.helpTRss2], accent: .orange)
                    }
                    OsmDisclosureRow(title: s.helpTAiTitle, systemImage: "sparkles", accent: .orange) {
                        OsmStepList(steps: [s.helpTAi1, s.helpTAi2, s.helpTAi3], accent: .orange)
                    }
                    OsmDisclosureRow(title: s.helpTFolderTitle, systemImage: "folder", accent: .orange) {
                        OsmStepList(steps: [s.helpTFolder1, s.helpTFolder2], accent: .orange)
                    }
                    OsmDisclosureRow(title: s.helpTSortTitle, systemImage: "arrow.up.arrow.down", accent: .orange) {
                        OsmStepList(steps: [s.helpTSort1], accent: .orange)
                    }
                }
                .osmSettingsCardRow()

                Section {
                    OsmDisclosureRow(title: s.helpTSearchTitle, systemImage: "magnifyingglass.circle", accent: .blue) {
                        OsmStepList(steps: [s.helpTSearch1], accent: .blue)
                    }
                    OsmDisclosureRow(title: s.helpTPlayTitle, systemImage: "play.circle", accent: .blue) {
                        OsmStepList(steps: [s.helpTPlay1], accent: .blue)
                    }
                    OsmDisclosureRow(title: s.helpTRandomTitle, systemImage: "shuffle", accent: .blue) {
                        OsmStepList(steps: [s.helpTRandom1, s.helpTRandom2], accent: .blue)
                    }
                    OsmDisclosureRow(title: s.helpTShakeTitle, systemImage: "iphone.radiowaves.left.and.right", accent: .blue) {
                        OsmStepList(steps: [s.helpTShake1, s.helpTShake2], accent: .blue)
                    }
                }
                .osmSettingsCardRow()

                Section {
                    OsmDisclosureRow(title: s.helpTBackupTitle, systemImage: "square.and.arrow.up", accent: .purple) {
                        OsmStepList(steps: [s.helpTBackup1], accent: .purple)
                    }
                    OsmDisclosureRow(title: s.helpTPlanTitle, systemImage: "crown", accent: .purple) {
                        OsmStepList(steps: [s.helpTPlan1], accent: .purple)
                    }
                }
                .osmSettingsCardRow()

                Section {
                    NavigationLink {
                        Group {
                            PrivacyView()
                        }
                        .osmSwipeToClose()
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
}

#Preview {
    HelpView()
        .environment(LanguageSettings())
        .environment(PlanStore.shared)
}

/// ヘルプと設定で使う開閉の行（丸いアイコン・見出し・開閉の印）。閉じて始まる。
struct OsmDisclosureRow<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: Color
    @State private var isExpanded = false
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        systemImage: String,
        accent: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.15), in: Circle())
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .tint(.secondary)
    }
}

/// 番号付きの手順。
struct OsmStepList: View {
    let steps: [String]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                        .frame(width: 16, alignment: .leading)
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

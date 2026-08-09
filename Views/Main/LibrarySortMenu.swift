import SwiftUI

struct LibrarySortToolbarMenu: View {
    @AppStorage("folderOrderOption") private var folderOrderRaw = FolderOrderOption.name.rawValue
    @AppStorage("episodeOrderOption") private var episodeOrderRaw = EpisodeOrderOption.date.rawValue
    @AppStorage("folderSortAscending") private var folderSortAscending = true
    @AppStorage("episodeSortAscending") private var episodeSortAscending = true
    @Environment(LanguageSettings.self) private var lang
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isPresented = false

    /// メニュー本体の幅（画面いっぱいに広がらないよう固定）
    private let panelWidth: CGFloat = 272

    private var folderOrder: FolderOrderOption {
        FolderOrderOption(rawValue: folderOrderRaw) ?? .name
    }

    private var episodeOrder: EpisodeOrderOption {
        EpisodeOrderOption(rawValue: episodeOrderRaw) ?? .date
    }

    var body: some View {
        let s = lang.strings
        Button {
            isPresented = true
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.14), in: Circle())
        }
        .accessibilityLabel(s.sortLabel)
        .modifier(SortMenuPresentationModifier(
            isPresented: $isPresented,
            usePopover: horizontalSizeClass == .regular,
            panel: { sortPanel(strings: s) }
        ))
    }

    private func sortPanel(strings s: LocalizedStrings) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(s.rootFolderReorderHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            folderControls(strings: s)

            Divider()

            episodeControls(strings: s)
        }
        .frame(width: panelWidth, alignment: .leading)
        .padding(20)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func folderControls(strings s: LocalizedStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.subfoldersSection)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            criterionRow(title: s.date, selected: folderOrder == .date) {
                folderOrderRaw = FolderOrderOption.date.rawValue
            }

            criterionRow(title: s.nameLabel, selected: folderOrder == .name) {
                folderOrderRaw = FolderOrderOption.name.rawValue
            }

            ascendingToggle(
                label: s.ascending,
                isOn: $folderSortAscending,
                onLabel: s.ascending_on,
                offLabel: s.ascending_off
            )
        }
    }

    private func episodeControls(strings s: LocalizedStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.episodes)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            criterionRow(title: s.date, selected: episodeOrder == .date) {
                episodeOrderRaw = EpisodeOrderOption.date.rawValue
            }

            criterionRow(title: s.nameLabel, selected: episodeOrder == .name) {
                episodeOrderRaw = EpisodeOrderOption.name.rawValue
            }

            ascendingToggle(
                label: s.ascending,
                isOn: $episodeSortAscending,
                onLabel: s.ascending_on,
                offLabel: s.ascending_off
            )
        }
    }

    private func ascendingToggle(
        label: String,
        isOn: Binding<Bool>,
        onLabel: String,
        offLabel: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.body)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(label)
                .accessibilityValue(isOn.wrappedValue ? onLabel : offLabel)
        }
    }

    private func criterionRow(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Group {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 18, alignment: .center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Presentation

private struct SortMenuPresentationModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let usePopover: Bool
    @ViewBuilder let panel: () -> Panel

    func body(content: Content) -> some View {
        if usePopover {
            content
                .popover(isPresented: $isPresented, arrowEdge: .top) {
                    panel()
                }
        } else {
            content
                .sheet(isPresented: $isPresented) {
                    SortMenuSheetContainer(content: panel)
                }
        }
    }
}

/// iPhone ではシートが全幅になるため、中身だけ固定幅で中央寄せする。
private struct SortMenuSheetContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .presentationDetents([.height(372)])
        .presentationDragIndicator(.visible)
    }
}

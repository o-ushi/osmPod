import SwiftUI
import SwiftData

struct FolderDropBar: View {
    let folders: [Folder]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(folders) { folder in
                    FolderDropChip(folder: folder)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct FolderDropChip: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @State private var isTargeted = false

    var body: some View {
        Label(folder.name, systemImage: folder.iconName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isTargeted ? Color.accentColor.opacity(0.25) : Color(.systemFill),
                in: Capsule()
            )
            .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
            .scaleEffect(isTargeted ? 1.08 : 1.0)
            .animation(.spring(duration: 0.2), value: isTargeted)
            .dropDestination(for: String.self) { feedURLs, _ in
                feedURLs.forEach { addShow(feedURL: $0, to: folder) }
                return true
            } isTargeted: { isTargeted = $0 }
    }

    @MainActor
    private func addShow(feedURL: String, to targetFolder: Folder) {
        let descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.feedURL == feedURL })
        guard let show = try? modelContext.fetch(descriptor).first else { return }
        guard !targetFolder.shows.contains(where: { $0.feedURL == feedURL }) else { return }
        targetFolder.shows.append(show)
        show.groups.append(targetFolder)
        try? modelContext.save()
    }
}

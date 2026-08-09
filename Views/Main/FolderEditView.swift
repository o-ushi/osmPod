import SwiftUI
import SwiftData

struct FolderEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore

    @State private var folderLimitMessage: String?

    @Query(sort: \Folder.sortOrder)
    private var allFolders: [Folder]

    var folder: Folder? = nil
    var parentFolder: Folder? = nil

    @State private var name: String = ""
    @State private var selectedIcon: String = "folder"

    private let iconRows: [[String]] = [
        ["folder",    "heart",      "star",        "bookmark"],
        ["clock",     "tray",       "archivebox",  "tag"],
        ["book.closed", "lightbulb", "headphones", "music.note"],
        ["mic",       "waveform",   "list.bullet", "checkmark.circle"],
    ]

    private func navigationTitle(strings s: LocalizedStrings) -> String {
        if folder != nil { return s.editFolder }
        return parentFolder != nil ? s.createSubfolder : s.createFolder
    }

    var body: some View {
        let s = lang.strings
        NavigationStack {
            Form {
                Section(s.folderName) {
                    TextField(s.folderName, text: $name)
                }

                if let parentFolder, folder == nil {
                    Section(s.parentFolder) {
                        Label(parentFolder.displayPath, systemImage: parentFolder.iconName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(s.icon) {
                    VStack(spacing: 8) {
                        ForEach(iconRows, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(row, id: \.self) { icon in
                                    iconCell(icon)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(navigationTitle(strings: s))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: {
                        Image(systemName: folder == nil ? "plus" : "checkmark")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let folder {
                    name = folder.name
                    selectedIcon = folder.iconName
                }
            }
            .alert(s.error, isPresented: Binding(
                get: { folderLimitMessage != nil },
                set: { if !$0 { folderLimitMessage = nil } }
            )) {
                Button(s.ok, role: .cancel) { folderLimitMessage = nil }
            } message: {
                Text(folderLimitMessage ?? "")
            }
        }
    }

    private func iconCell(_ icon: String) -> some View {
        let isSelected = selectedIcon == icon
        return Button {
            selectedIcon = icon
        } label: {
            Image(systemName: icon)
                .font(.title2)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    isSelected
                        ? AnyShapeStyle(.tint.opacity(0.15))
                        : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.tint, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let folder {
            folder.name = trimmedName
            folder.iconName = selectedIcon
        } else {
            do {
                try planStore.validateCanCreateFolder(context: modelContext)
            } catch {
                folderLimitMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
            let sortOrder: Int
            if let parentFolder {
                sortOrder = parentFolder.children.count
            } else {
                sortOrder = allFolders.filter(\.isRoot).count
            }
            let newFolder = Folder(
                name: trimmedName,
                iconName: selectedIcon,
                sortOrder: sortOrder,
                parent: parentFolder
            )
            modelContext.insert(newFolder)
        }
        try? modelContext.save()
        dismiss()
    }
}

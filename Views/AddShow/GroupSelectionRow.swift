import SwiftUI

struct GroupSelectionRow: View {
    let groupName: String
    var icon: String = "folder"
    var depth: Int = 0
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                if depth > 0 {
                    Color.clear.frame(width: CGFloat(depth) * 20)
                }
                Label(groupName, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
        }
        .buttonStyle(.plain)
    }
}

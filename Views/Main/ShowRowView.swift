import SwiftUI

struct ShowRowView: View {
    let show: Show
    var showsNewEpisodeIndicator: Bool
    private let newEpisodeIndicatorColor = Color(red: 0.67, green: 0.9, blue: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(show.title)
                    .font(.headline)
                    .foregroundStyle(AppPalette.textOnCardPrimary)
                    .multilineTextAlignment(.leading)
                if showsNewEpisodeIndicator {
                    Circle()
                        .fill(newEpisodeIndicatorColor)
                        .frame(width: 8, height: 8)
                }
                Spacer(minLength: 0)
            }
            Text(show.feedURL)
                .font(.caption)
                .foregroundStyle(AppPalette.textOnCardSecondary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

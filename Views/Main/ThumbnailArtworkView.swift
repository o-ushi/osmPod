import SwiftUI
import UIKit
import ImageIO

/// 番組アートワークまたはプレースホルダを正方形サムネイルとして表示する。
struct ThumbnailArtworkView: View {
    let artworkURLString: String?
    let placeholderSystemImage: String
    var cornerRadius: CGFloat = 6
    @State private var uiImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if resolvedArtworkURL != nil {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else if isLoading {
                    placeholder
                } else {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .task(id: resolvedArtworkURL?.absoluteString) {
            await loadImage()
        }
    }

    private var resolvedArtworkURL: URL? {
        guard let raw = artworkURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        guard var components = URLComponents(string: raw) else {
            return URL(string: raw)
        }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url ?? URL(string: raw)
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemFill)
            Image(systemName: placeholderSystemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func updateState(uiImage: UIImage?, isLoading: Bool) {
        self.uiImage = uiImage
        self.isLoading = isLoading
    }

    private func loadImage() async {
        guard let url = resolvedArtworkURL else {
            updateState(uiImage: nil, isLoading: false)
            return
        }

        updateState(uiImage: nil, isLoading: true)
        let data = await ThumbnailImageCache.shared.data(for: url)
        guard !Task.isCancelled else { return }
        let image = await decodeListThumbnail(from: data)
        guard !Task.isCancelled else { return }
        updateState(uiImage: image, isLoading: false)
    }
}

/// 一覧用に縮小デコードしてメインスレッドの負荷とスクロールのカクつきを抑える。
private func decodeListThumbnail(from data: Data?) async -> UIImage? {
    guard let data, !data.isEmpty else { return nil }
    return await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }.value
}

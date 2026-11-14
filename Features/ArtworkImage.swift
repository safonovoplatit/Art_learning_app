import SwiftUI
import UIKit

struct ArtworkImage: View {
    let artwork: Artwork
    let width: Int
    let pipeline: ImagePipeline
    var open: (() -> Void)?
    var parallax: CGFloat = 0
    var offline = false

    @State private var picture: UIImage?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        ZStack {
            if let picture {
                if let open {
                    Button(action: open) { thumbnail(picture) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть изображение")
                        .accessibilityIdentifier("open-artwork")
                } else {
                    thumbnail(picture).accessibilityHidden(true)
                }
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.title2)
                    Text("Изображение недоступно").font(.caption)
                    Button("Повторить") { retry += 1 }
                        .frame(minHeight: 44)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView().accessibilityLabel("Загрузка изображения")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: Request(url: artwork.imageURL(width: width), retry: retry, offline: offline)) {
            failed = false
            do {
                let result = try await pipeline.image(artwork.imageURL(width: width), pixels: width * 3 / 2)
                try Task.checkCancellation()
                picture = result
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private func thumbnail(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .offset(x: parallax)
    }

    private struct Request: Equatable {
        let url: URL
        let retry: Int
        let offline: Bool
    }
}

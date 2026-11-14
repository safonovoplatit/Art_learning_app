import SwiftUI
import UIKit

struct ArtworkImage: View {
    let artwork: Artwork
    let width: Int
    let pipeline: ImagePipeline
    var open: (() -> Void)?
    var offline = false
    var switchCollection: (() -> Void)?

    @State private var picture: UIImage?
    @State private var failed = false
    @State private var accessDenied = false
    @State private var retry = 0

    var body: some View {
        ZStack {
            if let picture {
                if let open {
                    Button(action: open) { thumbnail(picture) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть изображение")
                        .accessibilityIdentifier("open-artwork")
                        .accessibilityValue(Text(artwork.id))
                } else {
                    thumbnail(picture).accessibilityHidden(true)
                }
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.title2)
                    Text(accessDenied ? "Сервер музея отклонил загрузку" : "Изображение недоступно")
                        .font(.caption)
                    if accessDenied, let switchCollection {
                        Button("Открыть коллекцию Кливленда", action: switchCollection)
                            .frame(minHeight: 44)
                    }
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
            accessDenied = false
            do {
                let result = try await pipeline.image(artwork.imageURL(width: width), pixels: width * 3 / 2, fallback: artwork.fallbackImageURL(width: width))
                try Task.checkCancellation()
                picture = result
            } catch {
                if !Task.isCancelled {
                    if let failure = error as? MuseumAPIError, case .http(403) = failure {
                        accessDenied = true
                    }
                    failed = true
                }
            }
        }
    }

    private func thumbnail(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private struct Request: Equatable {
        let url: URL
        let retry: Int
        let offline: Bool
    }
}

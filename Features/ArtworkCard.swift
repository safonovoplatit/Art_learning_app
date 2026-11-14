import SwiftUI

struct ArtworkCard: View {
    let artwork: Artwork
    let width: Int
    let imageHeight: CGFloat
    let model: GalleryModel
    var parallax: CGFloat = 0
    let showImage: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ArtworkImage(artwork: artwork, width: width, pipeline: model.images, open: showImage, parallax: parallax, offline: model.offline)
                    .padding(20)
                    .frame(height: imageHeight)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipped()

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(artwork.title)
                                .font(.largeTitle.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("artwork-title")
                            Text(artwork.author).font(.title3).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            model.toggleFavorite(artwork)
                        } label: {
                            Image(systemName: model.isFavorite(artwork) ? "bookmark.fill" : "bookmark")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(.quaternary, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.isFavorite(artwork) ? "Удалить из избранного" : "Сохранить в избранное")
                        .accessibilityIdentifier("toggle-favorite")
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(artwork.localizedDate ?? String(localized: "Дата неизвестна"))
                        Text(location)
                        if let gallery = artwork.gallery {
                            Text("Зал по данным каталога: \(gallery)")
                                .font(.caption)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text(artwork.annotation)
                        .font(.body)
                        .lineSpacing(5)

                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Link(destination: artwork.sourceURL) {
                            Label("Страница произведения", systemImage: "arrow.up.right")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        Text("Изображение: \(artwork.imageRights)")
                        Link("Описание: Art Institute of Chicago, CC BY 4.0",
                             destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                        if artwork.translation != nil { Text("Название и аннотация переведены автоматически.") }
                        if let credit = artwork.credit { Text(credit) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("artwork-card")
    }

    private var location: String {
        if artwork.source == .chicago {
            return String(localized: "Чикагский институт искусств · Чикаго, США")
        }
        let parts = [artwork.museumName, artwork.city, artwork.country].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Местонахождение неизвестно") : parts.joined(separator: ", ")
    }
}

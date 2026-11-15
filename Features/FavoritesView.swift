import SwiftUI

struct FavoritesView: View {
    let model: GalleryModel
    let galleryWidth: Int
    @Environment(\.dismiss) private var dismiss
    @State private var viewer: Artwork?

    var body: some View {
        NavigationStack {
            Group {
                if model.favorites.isEmpty {
                    ContentUnavailableView("Здесь будут сохранённые картины", systemImage: "bookmark",
                                           description: Text("Добавьте произведение в избранное из галереи."))
                } else {
                    List {
                        ForEach(model.favorites) { work in
                            NavigationLink(value: work.id) {
                                HStack(spacing: 14) {
                                    ArtworkImage(artwork: work, width: 843, pipeline: model.images, offline: model.offline)
                                        .frame(width: 64, height: 58)
                                        .background(.quaternary)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(work.title)
                                            .font(.headline)
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(work.author).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .accessibilityIdentifier("favorite-row-\(work.id)")
                            .swipeActions {
                                Button("Удалить", role: .destructive) { model.toggleFavorite(work) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Избранное")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let artwork = model.favorites.first(where: { $0.id == id })
                    ?? model.artworks.first(where: { $0.id == id }) {
                    GeometryReader { geometry in
                        ArtworkCard(artwork: artwork, width: 843, imageHeight: max(170, geometry.size.height * 0.48),
                                    model: model, showImage: { viewer = artwork })
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .fullScreenCover(item: $viewer) { work in
            ArtworkViewer(artwork: work, width: galleryWidth, pipeline: model.images)
        }
    }
}

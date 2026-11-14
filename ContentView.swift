import SwiftUI
import UIKit

struct ContentView: View {
    let model: GalleryModel
    var translationEnabled = true
    @Environment(\.displayScale) private var scale
    @State private var showFavorites = false
    @State private var viewer: Artwork?
    @State private var haptic = 0

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            GeometryReader { geometry in
                let width = imageWidth(geometry.size.width)
                VStack(spacing: 0) {
                    if model.current != nil {
                        ArtworkPager(artworks: model.artworks, index: model.index, select: select) { work, parallax in
                            ArtworkCard(
                                artwork: work, width: width,
                                imageHeight: max(155, min(440, geometry.size.height * 0.49)),
                                model: model, parallax: parallax, showImage: { viewer = work }
                            )
                        }
                        footer
                    } else {
                        empty.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .task(id: PrefetchKey(id: model.current?.id, count: model.artworks.count, width: width, offline: model.offline)) {
                    await model.prefetch(width: width)
                }
                .task(id: FavoriteKey(artworks: model.favorites.map(\.imageBase), offline: model.offline)) {
                    await storeFavoriteImages()
                }
                .sheet(isPresented: $showFavorites) { FavoritesView(model: model, galleryWidth: width) }
                .fullScreenCover(item: $viewer) { work in
                    ArtworkViewer(artwork: work, width: width, pipeline: model.images)
                }
            }
            .navigationTitle("Галерея")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Избранное", systemImage: "bookmark") { showFavorites = true }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("favorites")
                }
            }
            .modifier(TranslationIfEnabled(model: model, enabled: translationEnabled))
        }
        .background(Color(uiColor: .systemBackground))
        .task {
            model.restore()
            await model.load()
        }
        .onChange(of: model.nearEnd) { _, needsMore in
            if needsMore { Task { await model.load() } }
        }
        .task { await model.observeConnectivity() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await model.images.clearMemory() }
        }
        .sensoryFeedback(.selection, trigger: haptic)
        .alert("Не удалось сохранить изменения", isPresented: $model.storageAlert) {
            Button("Закрыть", role: .cancel) {}
        }
    }

    @State private var pinned: Set<URL> = []

    private func storeFavoriteImages() async {
        // Use a fixed rendition so the saved file also works after rotation or on a different size class.
        let urls = Set(model.favorites.map { $0.imageURL(width: 843) })
        for removed in pinned.subtracting(urls) {
            await model.images.setFavorite(false, url: removed, pixels: 1264)
        }
        pinned = urls
        for url in urls {
            guard !Task.isCancelled else { return }
            await model.images.setFavorite(true, url: url, pixels: 1264)
        }
    }

    private func imageWidth(_ points: CGFloat) -> Int {
        points * scale > 640 ? 843 : 600
    }

    @ViewBuilder private var empty: some View {
        if !model.restored || model.loading {
            ProgressView("Загружаем коллекцию…")
        } else if let failure = model.failure {
            ContentUnavailableView {
                Label(failure == .offline ? "Нет интернета" : "Галерея недоступна", systemImage: "photo")
            } description: {
                Text(failure == .storage ? "Не удалось открыть локальную коллекцию." : "Не удалось загрузить произведения музея.")
            } actions: {
                Button("Повторить") { Task { await model.load(retry: true) } }.buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView {
                Label("Нет произведений", systemImage: "photo.on.rectangle")
            } actions: {
                if model.nextPage != nil {
                    Button("Загрузить ещё") { Task { await model.load(retry: true) } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 22)
            HStack {
                arrow("Предыдущее произведение", icon: "chevron.left", offset: -1)
                Spacer(minLength: 8)
                Group {
                    if model.loading && model.index == model.artworks.count - 1 {
                        ProgressView().accessibilityLabel("Загрузка коллекции")
                    } else if model.failure != nil && (!model.offline || model.index == model.artworks.count - 1) {
                        Button("Повторить") { Task { await model.load(retry: true) } }
                    } else if model.offline {
                        Label("Офлайн", systemImage: "wifi.slash")
                    } else if model.index == model.artworks.count - 1 {
                        if model.nextPage == nil {
                            Text("Конец коллекции")
                        } else {
                            Button("Загрузить ещё") { Task { await model.load(retry: true) } }
                        }
                    } else {
                        Text("Картина \(model.index + 1)").monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                arrow("Следующее произведение", icon: "chevron.right", offset: 1)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 2)
        }
        .accessibilityAction(named: Text("Следующее произведение")) { select(model.index + 1) }
        .accessibilityAction(named: Text("Предыдущее произведение")) { select(model.index - 1) }
    }

    private func arrow(_ title: LocalizedStringKey, icon: String, offset: Int) -> some View {
        Button {
            select(model.index + offset)
        } label: {
            Image(systemName: icon).font(.body.weight(.medium)).frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(offset > 0 ? "next-artwork" : "previous-artwork")
        .disabled(!model.artworks.indices.contains(model.index + offset))
        .opacity(model.artworks.indices.contains(model.index + offset) ? 1 : 0.25)
    }

    private func select(_ target: Int) {
        guard model.artworks.indices.contains(target), model.index != target else { return }
        model.select(target)
        haptic += 1
    }

    private struct PrefetchKey: Equatable {
        let id: String?
        let count: Int
        let width: Int
        let offline: Bool
    }

    private struct FavoriteKey: Equatable {
        let artworks: [URL]
        let offline: Bool
    }
}

private struct TranslationIfEnabled: ViewModifier {
    let model: GalleryModel
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.modifier(GalleryTranslation(model: model, service: TranslationService())) }
        else { content }
    }
}

import Observation
import SwiftUI
import Network

@MainActor @Observable
final class GalleryModel {
    enum Failure { case offline, network, storage }

    private let repository: any ArtworkRepository
    private let shuffleArtworks: Bool
    let images: ImagePipeline
    var artworks: [Artwork] = []
    var favorites: [Artwork] = []
    private(set) var index = 0
    private(set) var nextPage: Int? = 1
    private(set) var loading = false
    private(set) var restored = false
    private(set) var attemptedInitialLoad = false
    private(set) var failure: Failure?
    private(set) var offline = false
    var storageAlert = false

    var current: Artwork? { artworks.indices.contains(index) ? artworks[index] : nil }
    var nearEnd: Bool { artworks.count - index <= 6 }

    init(repository: any ArtworkRepository, images: ImagePipeline, shuffleArtworks: Bool = true) {
        self.repository = repository
        self.images = images
        self.shuffleArtworks = shuffleArtworks
    }

    func restore() {
        guard !restored else { return }
        do {
            let snapshot = try repository.restore()
            artworks = shuffleArtworks ? snapshot.artworks.shuffled() : snapshot.artworks
            favorites = snapshot.favorites
            index = shuffleArtworks ? 0 : (artworks.firstIndex { $0.id == snapshot.currentID } ?? 0)
            nextPage = snapshot.nextPage
            failure = nil
        } catch {
            failure = .storage
        }
        restored = true
    }

    func load(retry: Bool = false) async {
        if retry, failure == .storage {
            restored = false
            restore()
        }
        guard !loading, (retry || nearEnd), failure != .storage, retry || failure == nil,
              nextPage != nil else { return }
        loading = true
        failure = nil
        defer {
            loading = false
            if !Task.isCancelled { attemptedInitialLoad = true }
        }

        // Bound each batch, including pages that contain duplicates or unusable records.
        for _ in 0..<6 {
            guard let page = nextPage, nearEnd, !Task.isCancelled else { return }
            do {
                let loaded = try await repository.load(page: page, knownIDs: Set(artworks.map(\.id)))
                let selected = current?.id
                artworks.removeAll { loaded.restrictedIDs.contains($0.id) }
                favorites.removeAll { loaded.restrictedIDs.contains($0.id) }
                artworks.append(contentsOf: shuffleArtworks ? loaded.artworks.shuffled() : loaded.artworks)
                nextPage = loaded.nextPage
                index = artworks.firstIndex { $0.id == selected } ?? min(index, max(0, artworks.count - 1))
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
                failure = .offline
                return
            } catch {
                failure = .network
                return
            }
        }
    }

    func observeConnectivity() async {
        let monitor = NWPathMonitor()
        let updates = AsyncStream<Bool> { continuation in
            monitor.pathUpdateHandler = { path in continuation.yield(path.status != .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "gallery.connectivity"))
        }
        for await disconnected in updates {
            let wasOffline = offline
            offline = disconnected
            if !offline, wasOffline, failure == .offline || failure == .network {
                await load(retry: true)
            }
        }
    }

    func select(_ target: Int) {
        guard artworks.indices.contains(target), target != index else { return }
        index = target
        do { try repository.savePosition(artworks[target].id) }
        catch { storageAlert = true }
    }

    func isFavorite(_ artwork: Artwork) -> Bool { favorites.contains { $0.id == artwork.id } }

    func toggleFavorite(_ artwork: Artwork) {
        let saved = !isFavorite(artwork)
        do {
            try repository.setFavorite(artwork, saved: saved)
            if saved { favorites.insert(artwork, at: 0) }
            else { favorites.removeAll { $0.id == artwork.id } }
        } catch {
            storageAlert = true
        }
    }

    func prefetch(width: Int) async {
        let candidates = [index, index + 1, index - 1, index + 2, index - 2].compactMap {
            artworks.indices.contains($0) ? artworks[$0] : nil
        }
        for artwork in candidates {
            guard !Task.isCancelled else { return }
            _ = try? await images.image(artwork.imageURL(width: width), pixels: width * 3 / 2, fallback: artwork.fallbackImageURL(width: width))
        }
    }

    var translationCandidates: [Artwork] {
        let adjacent = [index, index + 1, index - 1].compactMap {
            artworks.indices.contains($0) ? artworks[$0] : nil
        }
        let priority = Set(adjacent.map(\.id))
        return (adjacent + artworks.filter { !priority.contains($0.id) }).filter { $0.translation == nil }
    }

    func apply(_ translation: ArtworkTranslation, to id: String) throws {
        try repository.saveTranslation(translation, for: id)
        if let i = artworks.firstIndex(where: { $0.id == id }), translation.matches(artworks[i]) {
            artworks[i].translation = translation
        }
        if let i = favorites.firstIndex(where: { $0.id == id }), translation.matches(favorites[i]) {
            favorites[i].translation = translation
        }
    }
}

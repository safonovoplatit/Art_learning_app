import Foundation
import SwiftData

@Model
final class StoredArtwork {
    @Attribute(.unique) var id: String
    var payload: Data
    var order: Int?
    var savedAt: Date?
    var viewedAt: Date?

    init(id: String, payload: Data, order: Int? = nil) {
        self.id = id
        self.payload = payload
        self.order = order
    }
}

@Model
final class StoredGallery {
    @Attribute(.unique) var key: String = "gallery"
    var currentID: String?
    var nextPage: Int? = 1

    init() {}
}

@MainActor
final class GalleryStore: ArtworkRepository {
    private let context: ModelContext
    private let provider: any MuseumAPIProvider
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer, provider: any MuseumAPIProvider) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.provider = provider
    }

    func restore() throws -> GallerySnapshot {
        let state = try context.fetch(FetchDescriptor<StoredGallery>()).first
        let rows = try context.fetch(FetchDescriptor<StoredArtwork>())
        let decoded = rows.compactMap { row in decode(row).map { (row, $0) } }
        return GallerySnapshot(
            artworks: decoded.filter { $0.0.order != nil }
                .sorted { ($0.0.order ?? 0) < ($1.0.order ?? 0) }.map { $0.1 },
            favorites: decoded.filter { $0.0.savedAt != nil }
                .sorted { ($0.0.savedAt ?? .distantPast) > ($1.0.savedAt ?? .distantPast) }.map { $0.1 },
            currentID: state?.currentID, nextPage: state == nil ? 1 : state?.nextPage
        )
    }

    func load(page: Int, knownIDs: Set<String>) async throws -> ArtworkPage {
        let result = try await provider.page(page)
        try Task.checkCancellation()
        var seen = knownIDs
        let rows = try context.fetch(FetchDescriptor<StoredArtwork>())
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var order = (rows.compactMap(\.order).max() ?? -1) + 1
        var additions: [Artwork] = []
        try transaction {
            for id in result.restrictedIDs {
                if let row = byID[id] { context.delete(row) }
            }
            for var artwork in result.artworks where !result.restrictedIDs.contains(artwork.id) {
                let existing = byID[artwork.id]
                guard !seen.contains(artwork.id) else { continue }
                if let existing, let translation = decode(existing)?.translation, translation.matches(artwork) {
                    artwork.translation = translation
                }
                if let existing {
                    existing.payload = try encoder.encode(artwork)
                }
                seen.insert(artwork.id)
                if let existing {
                    existing.order = order
                } else {
                    context.insert(StoredArtwork(id: artwork.id, payload: try encoder.encode(artwork), order: order))
                }
                order += 1
                additions.append(artwork)
            }
            try state().nextPage = result.nextPage
        }
        return ArtworkPage(artworks: additions, nextPage: result.nextPage, restrictedIDs: result.restrictedIDs)
    }

    func savePosition(_ id: String) throws {
        try transaction {
            try state().currentID = id
            try row(id)?.viewedAt = .now
        }
    }

    func setFavorite(_ artwork: Artwork, saved: Bool) throws {
        try transaction {
            if let row = try row(artwork.id) {
                row.savedAt = saved ? .now : nil
            } else if saved {
                let row = StoredArtwork(id: artwork.id, payload: try encoder.encode(artwork))
                row.savedAt = .now
                context.insert(row)
            }
        }
    }

    func saveTranslation(_ translation: ArtworkTranslation, for id: String) throws {
        guard let row = try row(id), var artwork = decode(row), translation.matches(artwork) else { return }
        try transaction {
            artwork.translation = translation
            row.payload = try encoder.encode(artwork)
        }
    }

    private func decode(_ row: StoredArtwork) -> Artwork? {
        guard var artwork = try? decoder.decode(Artwork.self, from: row.payload) else { return nil }
        if artwork.translation?.matches(artwork) == false { artwork.translation = nil }
        return artwork
    }

    private func row(_ id: String) throws -> StoredArtwork? {
        var descriptor = FetchDescriptor<StoredArtwork>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func state() throws -> StoredGallery {
        if let state = try context.fetch(FetchDescriptor<StoredGallery>()).first { return state }
        let new = StoredGallery()
        context.insert(new)
        return new
    }

    private func transaction(_ change: () throws -> Void) throws {
        do {
            try change()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

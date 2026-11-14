import Foundation

enum MuseumSource: String, Codable, Sendable {
    case chicago
}

struct Artwork: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let source: MuseumSource
    let originalTitle: String
    let originalArtist: String?
    let originalDescription: String
    let creationDate: String?
    let museumName: String?
    let city: String?
    let country: String?
    let gallery: String?
    let imageBase: URL
    let sourceURL: URL
    let isZoomable: Bool
    let imageRights: String
    let credit: String?
    let retrievedAt: Date

    var title: String { translation?.title ?? originalTitle }
    var annotation: String { translation?.annotation ?? originalDescription }
    var translation: ArtworkTranslation?

    var author: String {
        guard let originalArtist else { return String(localized: "Неизвестный автор") }
        return Self.artistNames[originalArtist] ?? originalArtist
    }

    var localizedDate: String? {
        creationDate?.replacingOccurrences(of: "c. ", with: String(localized: "ок. "))
    }

    func imageURL(width: Int) -> URL {
        imageBase.appending(path: "full").appending(path: "\(width),")
            .appending(path: "0").appending(path: "default.jpg")
    }

    private static let artistNames = [
        "Claude Monet": "Клод Моне", "Vincent van Gogh": "Винсент ван Гог",
        "Georges Seurat": "Жорж Сёра", "Gustave Caillebotte": "Гюстав Кайботт",
        "Camille Pissarro": "Камиль Писсарро", "Edgar Degas": "Эдгар Дега",
        "Paul Cézanne": "Поль Сезанн", "Édouard Manet": "Эдуар Мане",
        "Pierre-Auguste Renoir": "Пьер Огюст Ренуар", "Mary Cassatt": "Мэри Кэссетт",
        "Henri de Toulouse-Lautrec": "Анри де Тулуз-Лотрек", "Paul Gauguin": "Поль Гоген"
    ]
}

struct ArtworkTranslation: Codable, Hashable, Sendable {
    static let currentVersion = 1
    let title: String
    let annotation: String
    let sourceTitle: String
    let sourceAnnotation: String
    let sourceLanguage: String
    let targetLanguage: String
    let version: Int
    let updatedAt: Date

    func matches(_ artwork: Artwork) -> Bool {
        version == Self.currentVersion && sourceTitle == artwork.originalTitle
            && sourceAnnotation == artwork.originalDescription
            && sourceLanguage == "en" && targetLanguage == "ru"
    }
}

struct ArtworkPage: Sendable {
    let artworks: [Artwork]
    let nextPage: Int?
    let restrictedIDs: Set<String>
}

protocol MuseumAPIProvider: Sendable {
    func page(_ number: Int) async throws -> ArtworkPage
}

struct GallerySnapshot: Sendable {
    var artworks: [Artwork]
    var favorites: [Artwork]
    var currentID: String?
    var nextPage: Int?
}

@MainActor
protocol ArtworkRepository {
    func restore() throws -> GallerySnapshot
    func load(page: Int, knownIDs: Set<String>) async throws -> ArtworkPage
    func savePosition(_ id: String) throws
    func setFavorite(_ artwork: Artwork, saved: Bool) throws
    func saveTranslation(_ translation: ArtworkTranslation, for id: String) throws
}

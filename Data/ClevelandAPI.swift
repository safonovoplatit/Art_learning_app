import Foundation
import OSLog

struct ClevelandAPI: MuseumAPIProvider {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func page(_ number: Int) async throws -> ArtworkPage {
        let limit = 20
        var requestURL = URLComponents(string: "https://openaccess-api.clevelandart.org/api/artworks/")!
        requestURL.queryItems = [
            .init(name: "type", value: "Painting"),
            .init(name: "has_image", value: "1"),
            .init(name: "cc0", value: "1"),
            .init(name: "limit", value: String(limit))
        ]
        // The first page uses the server's default offset. An explicit skip=0 can return an empty result.
        if number > 1 {
            requestURL.queryItems?.append(.init(name: "skip", value: String((number - 1) * limit)))
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: URLRequest(url: requestURL.url!, timeoutInterval: 15))
        } catch {
            Logger(subsystem: "ArtGallery", category: "Cleveland").error("Catalog request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw MuseumAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            Logger(subsystem: "ArtGallery", category: "Cleveland").error("Catalog HTTP status: \(http.statusCode, privacy: .public)")
            throw MuseumAPIError.http(http.statusCode)
        }
        do {
            return try Self.decode(data, page: number, limit: limit)
        } catch {
            Logger(subsystem: "ArtGallery", category: "Cleveland").error("Catalog decode failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    static func decode(_ data: Data, page: Int, limit: Int) throws -> ArtworkPage {
        let result = try JSONDecoder().decode(ClevelandEnvelope.self, from: data)
        // Treat inconsistent empty pages as retryable instead of persisting a false end of the feed.
        if result.data.isEmpty && (page == 1 || (page - 1) * limit < result.info.total) {
            throw MuseumAPIError.invalidResponse
        }
        return ArtworkPage(
            artworks: result.data.compactMap { $0.artwork() },
            nextPage: page * limit < result.info.total && !result.data.isEmpty ? page + 1 : nil,
            restrictedIDs: Set(result.data.compactMap { work in
                guard let id = work.id, work.share_license_status != "CC0" else { return nil }
                return "cleveland:\(id)"
            })
        )
    }
}

private struct ClevelandEnvelope: Decodable {
    struct Info: Decodable { let total: Int }
    let info: Info
    let data: [ClevelandWork]
}

private struct ClevelandWork: Decodable {
    struct Creator: Decodable {
        let description: String?
        let role: String?
    }

    struct Images: Decodable {
        struct Rendition: Decodable { let url: URL? }
        let web: Rendition?
        let print: Rendition?
    }

    let id: Int?
    let title: String?
    let description: String?
    let wall_description: String?
    let creation_date: String?
    let creators: [Creator]?
    let share_license_status: String?
    let images: Images?
    let url: URL?
    let creditline: String?

    func artwork() -> Artwork? {
        guard share_license_status == "CC0", let id,
              let title = MuseumText.plain(title),
              let annotation = MuseumText.plain(description) ?? MuseumText.plain(wall_description),
              let webImage = cdnURL(images?.web?.url),
              let url, url.scheme == "https", ["clevelandart.org", "www.clevelandart.org"].contains(url.host ?? "")
        else { return nil }
        let artist = creators?.first { $0.role?.lowercased() == "artist" }?.description
        let largeImage = cdnURL(images?.print?.url)
        var artwork = Artwork(
            id: "cleveland:\(id)", source: .cleveland, originalTitle: title,
            originalArtist: MuseumText.plain(artist), originalDescription: annotation,
            creationDate: MuseumText.plain(creation_date), museumName: "Cleveland Museum of Art",
            city: "Cleveland", country: "United States", imageBase: webImage, sourceURL: url,
            imageRights: "CC0 1.0",
            credit: MuseumText.plain(creditline), retrievedAt: .now
        )
        artwork.largeImageURL = largeImage
        return artwork
    }

    private func cdnURL(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.host == "openaccess-cdn.clevelandart.org" else { return nil }
        return url
    }
}

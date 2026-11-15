import Foundation

struct HarvardAPI: MuseumAPIProvider {
    let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        self.session = session ?? URLSession(configuration: config)
    }

    func page(_ number: Int) async throws -> ArtworkPage {
        var url = URLComponents(string: "https://api.harvardartmuseums.org/object")!
        url.queryItems = [
            .init(name: "apikey", value: apiKey),
            .init(name: "classification", value: "Paintings"),
            .init(name: "hasimage", value: "1"),
            .init(name: "q", value: "description:*"),
            .init(name: "size", value: "30"),
            .init(name: "page", value: String(number))
        ]
        let (data, response) = try await session.data(for: URLRequest(url: url.url!, timeoutInterval: 15))
        guard let http = response as? HTTPURLResponse else { throw MuseumAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MuseumAPIError.http(http.statusCode) }
        return try Self.decode(data, number: number)
    }

    static func decode(_ data: Data, number: Int) throws -> ArtworkPage {
        let envelope = try JSONDecoder().decode(HarvardEnvelope.self, from: data)
        return ArtworkPage(
            artworks: envelope.records.compactMap { $0.artwork() },
            nextPage: number < envelope.info.pages && !envelope.records.isEmpty ? number + 1 : nil,
            restrictedIDs: Set(envelope.records.compactMap {
                guard let id = $0.objectid, $0.imagepermissionlevel != 0 else { return nil }
                return "harvard:\(id)"
            })
        )
    }
}

private struct HarvardEnvelope: Decodable {
    struct Info: Decodable { let pages: Int }
    let info: Info
    let records: [HarvardWork]
}

private struct HarvardWork: Decodable {
    struct Person: Decodable {
        let name: String?
        let role: String?
    }

    struct MuseumImage: Decodable {
        let baseimageurl: URL?
        let copyright: String?
    }

    let objectid: Int?
    let title: String?
    let dated: String?
    let description: String?
    let labeltext: String?
    let people: [Person]?
    let primaryimageurl: URL?
    let images: [MuseumImage]?
    let imagepermissionlevel: Int?
    let creditline: String?
    let copyright: String?

    func artwork() -> Artwork? {
        guard imagepermissionlevel == 0, let id = objectid,
              let title = MuseumText.plain(title),
              let annotation = MuseumText.plain(description) ?? MuseumText.plain(labeltext),
              let image = primaryimageurl, image.scheme == "https", image.host == "nrs.harvard.edu"
        else { return nil }
        let artist = people?.first { $0.role?.lowercased() == "artist" }?.name
        let imageCopyright = images?.first { $0.baseimageurl == image }?.copyright
        return Artwork(
            id: "harvard:\(id)", source: .harvard, originalTitle: title,
            originalArtist: MuseumText.plain(artist), originalDescription: annotation,
            creationDate: MuseumText.plain(dated), museumName: "Harvard Art Museums",
            city: "Cambridge", country: "United States",
            imageBase: image, sourceURL: URL(string: "https://harvardartmuseums.org/collections/object/\(id)")!,
            imageRights: MuseumText.plain(imageCopyright ?? copyright) ?? "Harvard Art Museums",
            credit: MuseumText.plain(creditline), retrievedAt: .now
        )
    }
}

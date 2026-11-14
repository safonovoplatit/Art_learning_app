import Foundation

enum MuseumAPIError: Error {
    case invalidResponse
    case http(Int)
}

struct ChicagoAPI: MuseumAPIProvider {
    let session: URLSession
    private let endpoint = URL(string: "https://api.artic.edu/api/v1/artworks/search")!
    private static let fields = "id,title,artist_title,date_display,short_description,description,image_id,is_public_domain,is_zoomable,gallery_title,artwork_type_title,credit_line"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func page(_ number: Int) async throws -> ArtworkPage {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        // A positive match for image and description reduces empty pages. Rights are checked again on import.
        let filter = #"{"bool":{"filter":[{"term":{"is_public_domain":true}},{"exists":{"field":"image_id"}},{"bool":{"should":[{"exists":{"field":"description"}},{"exists":{"field":"short_description"}}],"minimum_should_match":1}}],"should":[{"match":{"artwork_type_title":"Painting"}}]}}"#
        let params = #"{"query":\#(filter),"fields":"\#(Self.fields)","limit":40,"page":\#(number),"from":\#((number - 1) * 40)}"#
        components.queryItems = [.init(name: "params", value: params)]
        let data = try await fetch(components.url!)
        return try Self.decode(data, number: number)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("ArtGallery-iOS/1.0", forHTTPHeaderField: "AIC-User-Agent")
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw MuseumAPIError.invalidResponse }
                if (200..<300).contains(response.statusCode) { return data }
                if attempt < 2, response.statusCode == 429 || (500..<600).contains(response.statusCode) {
                    let backoff = Double(1 << attempt)
                    let header = response.value(forHTTPHeaderField: "Retry-After")
                    let wait = header.flatMap(Double.init) ?? backoff
                    guard wait.isFinite, wait <= 30 else { throw MuseumAPIError.http(response.statusCode) }
                    try await Task.sleep(for: .seconds(max(backoff, wait)))
                    continue
                }
                throw MuseumAPIError.http(response.statusCode)
            } catch let error as URLError where attempt < 2 && [.timedOut, .networkConnectionLost].contains(error.code) {
                try await Task.sleep(for: .seconds(1 << attempt))
            }
        }
        throw MuseumAPIError.invalidResponse
    }

    static func decode(_ data: Data, number: Int) throws -> ArtworkPage {
        let envelope = try JSONDecoder().decode(ChicagoEnvelope.self, from: data)
        let base = envelope.config.iiif_url
        guard base.scheme == "https", base.host != nil else { throw MuseumAPIError.invalidResponse }
        let ordered = envelope.data.enumerated().sorted { first, second in
            let a = first.element.priority
            let b = second.element.priority
            return a == b ? first.offset < second.offset : a > b
        }
        return ArtworkPage(
            artworks: ordered.compactMap { $0.element.artwork(base: base) },
            nextPage: number < envelope.pagination.total_pages && !envelope.data.isEmpty ? number + 1 : nil,
            restrictedIDs: Set(envelope.data.compactMap {
                guard $0.is_public_domain == false, let id = $0.id else { return nil }
                return "chicago:\(id)"
            })
        )
    }
}

private struct ChicagoEnvelope: Decodable {
    struct Config: Decodable { let iiif_url: URL }
    struct Pagination: Decodable { let total_pages: Int }
    let config: Config
    let pagination: Pagination
    let data: [ChicagoWork]
}

private struct ChicagoWork: Decodable {
    let id: Int?
    let title: String?
    let artist_title: String?
    let date_display: String?
    let short_description: String?
    let description: String?
    let image_id: String?
    let is_public_domain: Bool?
    let is_zoomable: Bool?
    let gallery_title: String?
    let artwork_type_title: String?
    let credit_line: String?

    var priority: Int {
        (artwork_type_title?.lowercased() == "painting" ? 4 : 0)
            + (short_description == nil ? 0 : 2) + (artist_title == nil ? 0 : 1)
    }

    func artwork(base: URL) -> Artwork? {
        guard is_public_domain == true, let id, let image_id, UUID(uuidString: image_id) != nil,
              let title = MuseumText.plain(title),
              let annotation = MuseumText.plain(short_description) ?? MuseumText.plain(description)
        else { return nil }
        return Artwork(
            id: "chicago:\(id)", source: .chicago, originalTitle: title,
            originalArtist: MuseumText.plain(artist_title), originalDescription: annotation,
            creationDate: MuseumText.plain(date_display), museumName: "Art Institute of Chicago",
            city: "Chicago", country: "United States", gallery: MuseumText.plain(gallery_title),
            imageBase: base.appending(path: image_id),
            sourceURL: URL(string: "https://www.artic.edu/artworks/\(id)")!,
            isZoomable: is_zoomable == true, imageRights: "CC0 1.0",
            credit: MuseumText.plain(credit_line), retrievedAt: .now
        )
    }
}

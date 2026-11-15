#if ART_GALLERY_TEST_TARGET
import SwiftData
import SwiftUI
import XCTest
@testable import ArtGallery

@MainActor
final class GalleryTests: XCTestCase {
    func testClevelandUsesItsOwnCC0ImagesAndPaginates() throws {
        let response = Data("""
        {"info":{"total":25},"data":[
          {"id":94979,"title":"Nathaniel Hurd","description":"Portrait","share_license_status":"CC0",
           "url":"https://clevelandart.org/art/1915.534",
           "images":{"web":{"url":"https://openaccess-cdn.clevelandart.org/web.jpg"},
                     "print":{"url":"https://openaccess-cdn.clevelandart.org/print.jpg"}}},
          {"id":9,"title":"Restricted","share_license_status":"Copyrighted"}
        ]}
        """.utf8)
        let page = try ClevelandAPI.decode(response, page: 1, limit: 20)
        let work = try XCTUnwrap(page.artworks.first)
        XCTAssertEqual(page.artworks.map(\.id), ["cleveland:94979"])
        XCTAssertEqual(page.restrictedIDs, ["cleveland:9"])
        XCTAssertEqual(page.nextPage, 2)
        XCTAssertEqual(work.imageURL(width: 843).lastPathComponent, "web.jpg")
        XCTAssertEqual(work.imageURL(width: 1800).lastPathComponent, "print.jpg")
    }

    func testHarvardFiltersImagePermissionsAndPaginates() throws {
        let response = Data("""
        {"info":{"pages":2},"records":[
          {"objectid":1429,"title":"Landscape","description":"<p>Mist &amp; trees.</p>",
           "imagepermissionlevel":0,"primaryimageurl":"https://nrs.harvard.edu/urn-3:HUAM:79762_dynmc",
           "people":[{"name":"Lee Chun-Yi","role":"Artist"}]},
          {"objectid":12455,"title":"Restricted","description":"Text","imagepermissionlevel":1}
        ]}
        """.utf8)
        let page = try HarvardAPI.decode(response, number: 1)
        XCTAssertEqual(page.nextPage, 2)
        XCTAssertEqual(page.restrictedIDs, ["harvard:12455"])
        XCTAssertEqual(page.artworks.map(\.id), ["harvard:1429"])
        XCTAssertEqual(page.artworks.first?.originalDescription, "Mist & trees.")
        XCTAssertEqual(page.artworks.first?.source, .harvard)
    }

    func testMuseumImageRejectionUsesAlternateRenditionAndCachesIt() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFallbackProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let museum = URL(string: "https://images.example.test/web.jpg")!
        let alternate = URL(string: "https://images.example.test/print.jpg")!
        let session = URLSession(configuration: configuration)
        let pipeline = ImagePipeline(session: session, cacheDirectory: directory)

        let image = try await pipeline.image(museum, pixels: 128, fallback: alternate)
        XCTAssertEqual(image.cgImage?.width, 96)
        let reopened = ImagePipeline(session: session, cacheDirectory: directory)
        let cached = try await reopened.image(museum, pixels: 128)
        XCTAssertEqual(cached.cgImage?.width, 96)
    }

    func testHTMLRemovesExecutableAndInvisibleContent() {
        XCTAssertEqual(MuseumText.plain("<p>Tea &amp; coffee</p><script>alert(1)</script><p>1880<br>Paris</p>"),
                       "Tea & coffee 1880 Paris")
        XCTAssertNil(MuseumText.plain("<p>&nbsp;</p>"))
    }

    func testTranslationExpandsCatalogAbbreviationsButKeepsInitials() {
        let source = "J.C. 1880; ca. 1890; approx.1900; No. 5; figs. 2–3; Vol. 4; St. Paul."
        XCTAssertEqual(MuseumText.expandingAbbreviations(in: source),
                       "J.C. 1880; circa 1890; circa 1900; number 5; figures 2–3; volume 4; St. Paul.")
    }

    func testStorageRestoresPositionFavoritesAndTranslationAcrossContexts() async throws {
        let page = try ClevelandAPI.decode(Self.museumResponse, page: 1, limit: 20)
        let work = try XCTUnwrap(page.artworks.first)
        XCTAssertEqual(work.localizedDate, "ок.\u{00A0}1880")
        let container = try ModelContainer(for: StoredArtwork.self, StoredGallery.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let provider = StubProvider(result: .success(page))
        let store = GalleryStore(container: container, provider: provider)
        let added = try await store.load(page: 1, knownIDs: [])
        XCTAssertEqual(added.artworks.count, 1)
        try store.savePosition(work.id)
        try store.setFavorite(work, saved: true)
        let translation = ArtworkTranslation(title: "Картина", annotation: "Аннотация",
                                             sourceTitle: work.originalTitle, sourceAnnotation: work.originalDescription,
                                             sourceLanguage: "en", targetLanguage: "ru",
                                             version: ArtworkTranslation.currentVersion)
        try store.saveTranslation(translation, for: work.id)
        let reopened = GalleryStore(container: container, provider: provider)
        let duplicate = try await reopened.load(page: 2, knownIDs: [work.id])
        XCTAssertTrue(duplicate.artworks.isEmpty)
        let snapshot = try reopened.restore()
        XCTAssertEqual(snapshot.currentID, work.id)
        XCTAssertEqual(snapshot.favorites.map(\.id), [work.id])
        XCTAssertEqual(snapshot.artworks.first?.translation, translation)
        try reopened.setFavorite(work, saved: false)
        XCTAssertTrue(try reopened.restore().favorites.isEmpty)
    }

    func testLegacyChicagoFavoriteIsHidden() throws {
        let work = try XCTUnwrap(ClevelandAPI.decode(Self.museumResponse, page: 1, limit: 20).artworks.first)
        let container = try ModelContainer(for: StoredArtwork.self, StoredGallery.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let payload = try JSONEncoder().encode(work)
        let legacy = try XCTUnwrap(String(data: payload, encoding: .utf8))
            .replacingOccurrences(of: #""source":"cleveland""#, with: #""source":"chicago""#)
        let row = StoredArtwork(id: "chicago:123", payload: Data(legacy.utf8), order: 0)
        row.savedAt = .now
        context.insert(row)
        try context.save()
        let store = GalleryStore(container: container, provider: StubProvider(result: .failure(URLError(.notConnectedToInternet))))
        let snapshot = try store.restore()
        XCTAssertTrue(snapshot.artworks.isEmpty)
        XCTAssertTrue(snapshot.favorites.isEmpty)
    }

    func testOfflineErrorRetainsRetryablePage() async throws {
        let container = try ModelContainer(for: StoredArtwork.self, StoredGallery.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = GalleryStore(container: container, provider: StubProvider(result: .failure(URLError(.notConnectedToInternet))))
        let model = GalleryModel(repository: repository, images: ImagePipeline())
        model.restore()
        await model.load()
        XCTAssertEqual(model.failure, .offline)
        XCTAssertEqual(model.nextPage, 1)
        XCTAssertFalse(model.loading)
    }


    private static let museumResponse = Data("""
    {"info":{"total":25},"data":[
      {"id":94979,"title":"Work","description":"Oil &amp; canvas.","creation_date":"ca. 1880","share_license_status":"CC0",
       "url":"https://clevelandart.org/art/1915.534",
       "images":{"web":{"url":"https://openaccess-cdn.clevelandart.org/web.jpg"}}}
    ]}
    """.utf8)
}

private struct StubProvider: MuseumAPIProvider {
    let result: Result<ArtworkPage, URLError>
    func page(_ number: Int) async throws -> ArtworkPage { try result.get() }
}
private final class ImageFallbackProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let available = url.lastPathComponent == "print.jpg"
        let response = HTTPURLResponse(url: url, statusCode: available ? 200 : 403, httpVersion: nil,
                                       headerFields: ["Content-Type": available ? "image/png" : "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if available {
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAGAAAABACAIAAABqVuVZAAAAaUlEQVR42u3QMQ0AAAgDsClGAALQjQNujiZV0FQPhygQJEiQIEGCBAlCkCBBggQJEiQIQYIECRIkSJAgBAkSJEiQIEGCBCFIkCBBggQJEoQgQYIECRIkSBCCBAkSJEiQIEGCECRIkKB/Fq1wUf/3BgnOAAAAAElFTkSuQmCC")!
            client?.urlProtocol(self, didLoad: png)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif

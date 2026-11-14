import SwiftData
import SwiftUI
import XCTest
@testable import ArtGallery

@MainActor
final class GalleryTests: XCTestCase {
    func testDecodingFiltersRestrictedAndUndescribedWorks() throws {
        let page = try ChicagoAPI.decode(Self.museumResponse, number: 1)
        XCTAssertEqual(page.nextPage, 2)
        XCTAssertEqual(page.restrictedIDs, ["chicago:2"])
        let artwork = try XCTUnwrap(page.artworks.first)
        XCTAssertEqual(page.artworks.map(\.id), ["chicago:1"])
        XCTAssertEqual(artwork.originalDescription, "Oil & canvas. Second line.")
        XCTAssertEqual(artwork.author, "Клод Моне")
        XCTAssertEqual(artwork.city, "Chicago")
        XCTAssertEqual(artwork.imageURL(width: 843).lastPathComponent, "default.jpg")
        XCTAssertTrue(artwork.imageURL(width: 843).path.contains("/full/843,/0/"))
    }

    func testHTMLRemovesExecutableAndInvisibleContent() {
        XCTAssertEqual(MuseumText.plain("<p>Tea &amp; coffee</p><script>alert(1)</script><p>1880<br>Paris</p>"),
                       "Tea & coffee 1880 Paris")
        XCTAssertNil(MuseumText.plain("<p>&nbsp;</p>"))
    }

    func testStorageRestoresPositionFavoritesAndTranslationAcrossContexts() async throws {
        let page = try ChicagoAPI.decode(Self.museumResponse, number: 1)
        let work = try XCTUnwrap(page.artworks.first)
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
                                             sourceLanguage: "en", targetLanguage: "ru", version: 1, updatedAt: .now)
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

    func testSwipeThresholdAndDirection() {
        XCTAssertEqual(ArtworkPager<EmptyView>.direction(distance: -65, prediction: -75, width: 390), 0)
        XCTAssertEqual(ArtworkPager<EmptyView>.direction(distance: -45, prediction: -180, width: 390), 1)
        XCTAssertEqual(ArtworkPager<EmptyView>.direction(distance: 100, prediction: 112, width: 390), -1)
        XCTAssertEqual(ArtworkPager<EmptyView>.direction(distance: 25, prediction: -180, width: 390), 0)
    }

    private static let museumResponse = Data("""
    {"data":[
      {"id":1,"title":"Work","artist_title":"Claude Monet","date_display":"1880","description":"<p>Oil &amp; canvas.</p><p>Second line.</p>",
       "image_id":"9ca31052-95e9-35a0-7199-612a388be307","is_public_domain":true,"artwork_type_title":"Painting"},
      {"id":2,"title":"Restricted","is_public_domain":false,"description":"Hidden"},
      {"id":3,"title":"No annotation","image_id":"9ca31052-95e9-35a0-7199-612a388be307","is_public_domain":true}
    ],"config":{"iiif_url":"https://www.artic.edu/iiif/2"},"pagination":{"total_pages":2}}
    """.utf8)
}

private struct StubProvider: MuseumAPIProvider {
    let result: Result<ArtworkPage, URLError>
    func page(_ number: Int) async throws -> ArtworkPage { try result.get() }
}

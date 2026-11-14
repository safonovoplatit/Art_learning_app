#if DEBUG
import Foundation

struct GalleryFixture: MuseumAPIProvider {
    func page(_ number: Int) async throws -> ArtworkPage {
        let works = ["Первая картина", "Вторая картина", "Третья картина"].enumerated().map { i, title in
            Artwork(id: "cleveland:\(i)", source: .cleveland, originalTitle: title, originalArtist: "Claude Monet",
                    originalDescription: "Аннотация для проверки галереи.", creationDate: "1880",
                    museumName: "Cleveland Museum of Art", city: "Cleveland", country: "United States", gallery: nil,
                    imageBase: URL(string: "https://fixture.invalid/\(i)")!,
                    sourceURL: URL(string: "https://clevelandart.org/art/1915.534")!,
                    isZoomable: true, imageRights: "CC0 1.0", credit: nil, retrievedAt: .now)
        }
        return ArtworkPage(artworks: works, nextPage: nil, restrictedIDs: [])
    }
}

final class GalleryFixtureImage: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Cache-Control": "no-store", "Content-Type": "image/png"]),
              let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAGAAAABACAIAAABqVuVZAAAAaUlEQVR42u3QMQ0AAAgDsClGAALQjQNujiZV0FQPhygQJEiQIEGCBAlCkCBBggQJEiQIQYIECRIkSJAgBAkSJEiQIEGCBCFIkCBBggQJEoQgQYIECRIkSBCCBAkSJEiQIEGCECRIkKB/Fq1wUf/3BgnOAAAAAElFTkSuQmCC")
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: image)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif

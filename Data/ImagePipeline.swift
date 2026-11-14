import CryptoKit
import Foundation
import ImageIO
import OSLog
import UIKit

actor ImagePipeline {
    private struct Flight {
        let task: Task<Void, Never>
        let id: UUID
        var waiters: [UUID: CheckedContinuation<UIImage, Error>]
    }

    private let logger = Logger(subsystem: "ArtGallery", category: "Images")
    private let memory = NSCache<NSURL, UIImage>()
    private let files = FileManager.default
    private let cacheDirectory: URL
    private let favoritesDirectory: URL
    private let session: URLSession
    private var running: [URL: Flight] = [:]
    private var keepOffline: Set<URL> = []

    init(session: URLSession? = nil, cacheDirectory: URL? = nil, favoritesDirectory: URL? = nil) {
        let manager = FileManager.default
        self.cacheDirectory = cacheDirectory ?? manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "GalleryImages")
        self.favoritesDirectory = favoritesDirectory ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GalleryFavorites")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.urlCache = URLCache(memoryCapacity: 4_000_000, diskCapacity: 0)
        config.httpMaximumConnectionsPerHost = 4
        self.session = session ?? URLSession(configuration: config)
        memory.totalCostLimit = 48_000_000
    }

    func image(_ url: URL, pixels: Int, fallback: URL? = nil) async throws -> UIImage {
        try Task.checkCancellation()
        if let image = memory.object(forKey: url as NSURL) { return image }
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if var flight = running[url] {
                    flight.waiters[token] = continuation
                    running[url] = flight
                } else {
                    let id = UUID()
                    let task = Task { await self.fetch(url, pixels: pixels, fallback: fallback, id: id) }
                    running[url] = Flight(task: task, id: id, waiters: [token: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(url, token: token) }
        }
    }

    func setFavorite(_ saved: Bool, url: URL, pixels: Int, fallback: URL? = nil) async {
        let local = location(url, in: favoritesDirectory)
        if saved {
            keepOffline.insert(url)
            if files.fileExists(atPath: local.path) { return }
            if let data = try? Data(contentsOf: location(url, in: cacheDirectory)) {
                persist(data, url: url, favorite: true)
            } else {
                memory.removeObject(forKey: url as NSURL)
                _ = try? await image(url, pixels: pixels, fallback: fallback)
            }
        } else {
            keepOffline.remove(url)
            try? files.removeItem(at: local)
        }
    }

    func clearMemory() { memory.removeAllObjects() }

    private func cancel(_ url: URL, token: UUID) {
        guard var flight = running[url], let waiter = flight.waiters.removeValue(forKey: token) else { return }
        waiter.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            flight.task.cancel()
            running.removeValue(forKey: url)
        } else {
            running[url] = flight
        }
    }

    private func fetch(_ url: URL, pixels: Int, fallback: URL?, id: UUID) async {
        let result: Result<UIImage, Error>
        do {
            let image = try await load(url, pixels: pixels, fallback: fallback)
            result = .success(image)
        } catch {
            if !Task.isCancelled {
                logger.error("Image unavailable (primary host \(url.host ?? "", privacy: .public)): \(String(describing: error), privacy: .public)")
            }
            result = .failure(error)
        }
        guard running[url]?.id == id else { return }
        if let flight = running.removeValue(forKey: url) {
            for waiter in flight.waiters.values { waiter.resume(with: result) }
        }
    }

    private func load(_ url: URL, pixels: Int, fallback: URL?) async throws -> UIImage {
        for directory in [favoritesDirectory, cacheDirectory] {
            let file = location(url, in: directory)
            guard let data = try? Data(contentsOf: file) else { continue }
            if let image = decode(data, pixels: pixels) {
                try? files.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
                return remember(image, url: url)
            }
            try? files.removeItem(at: file)
        }
        let data: Data
        let http: HTTPURLResponse
        let image: UIImage
        do {
            (data, http, image) = try await download(url, pixels: pixels)
        } catch {
            try Task.checkCancellation()
            guard let fallback else { throw error }
            (data, http, image) = try await download(fallback, pixels: pixels)
        }
        try Task.checkCancellation()
        let cacheControl = http.value(forHTTPHeaderField: "Cache-Control")?.lowercased() ?? ""
        if url.host != "nrs.harvard.edu", !cacheControl.contains("no-store") {
            persist(data, url: url, favorite: keepOffline.contains(url))
        }
        return remember(image, url: url)
    }

    private func download(_ url: URL, pixels: Int) async throws -> (Data, HTTPURLResponse, UIImage) {
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if attempt == 0, (500...599).contains(http.statusCode) {
                    try await Task.sleep(for: .milliseconds(400))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else { throw MuseumAPIError.http(http.statusCode) }
                guard data.count <= 24_000_000, let image = decode(data, pixels: pixels) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return (data, http, image)
            } catch let error as URLError where attempt == 0 && [.timedOut, .networkConnectionLost].contains(error.code) {
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        throw URLError(.badServerResponse)
    }

    private func decode(_ data: Data, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    private func remember(_ image: UIImage, url: URL) -> UIImage {
        if let bitmap = image.cgImage {
            memory.setObject(image, forKey: url as NSURL, cost: bitmap.bytesPerRow * bitmap.height)
        }
        return image
    }

    private func location(_ url: URL, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).description
        return directory.appending(path: String(digest.suffix(64)))
    }

    private func persist(_ data: Data, url: URL, favorite: Bool) {
        let directory = favorite ? favoritesDirectory : cacheDirectory
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            if favorite {
                var folder = directory
                var settings = URLResourceValues()
                settings.isExcludedFromBackup = true
                try? folder.setResourceValues(settings)
            }
            try data.write(to: location(url, in: directory), options: .atomic)
            evict(from: directory, limit: favorite ? 100_000_000 : 300_000_000)
        } catch {
            // A full disk should not prevent displaying the downloaded artwork.
        }
    }

    private func evict(from directory: URL, limit: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let entries = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let dated = entries.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        var total = dated.reduce(0) { $0 + $1.1 }
        guard total > limit else { return }
        for (url, size, _) in dated.sorted(by: { $0.2 < $1.2 }) where total > limit {
            if (try? files.removeItem(at: url)) != nil { total -= size }
        }
    }
}

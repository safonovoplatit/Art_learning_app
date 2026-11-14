import SwiftData
import SwiftUI

@main
struct MyApp: App {
    @AppStorage("gallery.museum.offlineStarter") private var museum = MuseumSource.cleveland
    @State private var model: GalleryModel?
    @State private var activeMuseum: MuseumSource?
    @State private var startupFailed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let model, activeMuseum == selectedMuseum {
                    ContentView(model: model, translationEnabled: !Self.isUITest,
                                museum: selectedMuseum, museums: Self.availableMuseums,
                                selectMuseum: { museum = $0 })
                        .id(selectedMuseum)
                } else if startupFailed {
                    ContentUnavailableView {
                        Label("Не удалось открыть локальную коллекцию", systemImage: "externaldrive")
                    } actions: {
                        Button("Повторить", action: start)
                    }
                } else {
                    ProgressView("Открываем галерею…")
                }
            }
            .task(id: selectedMuseum) { start() }
        }
    }

    private static var isLiveGalleryTest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--live-cleveland-test")
        #else
        false
        #endif
    }

    private static var isUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    private static var harvardKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "HarvardAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var availableMuseums: [MuseumSource] {
        if isUITest { return [] }
        return harvardKey.isEmpty ? [.cleveland] : [.cleveland, .harvard]
    }

    private var selectedMuseum: MuseumSource {
        Self.availableMuseums.contains(museum) ? museum : .cleveland
    }

    private func start() {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: Self.isUITest || Self.isLiveGalleryTest)
            let container = try ModelContainer(for: StoredArtwork.self, StoredGallery.self, configurations: config)
            var source = Self.isLiveGalleryTest ? .cleveland : selectedMuseum
            var provider: any MuseumAPIProvider
            switch source {
            case .cleveland: provider = ClevelandAPI()
            case .harvard: provider = HarvardAPI(apiKey: Self.harvardKey)
            }
            var images = ImagePipeline()
            #if DEBUG
            if Self.isUITest {
                let testSession = URLSessionConfiguration.ephemeral
                testSession.protocolClasses = [GalleryFixtureImage.self]
                provider = GalleryFixture()
                source = .cleveland
                images = ImagePipeline(session: URLSession(configuration: testSession))
            }
            #endif
            let store = GalleryStore(container: container, provider: provider, source: source)
            model = GalleryModel(repository: store, images: images,
                                 shuffleArtworks: !Self.isUITest && !Self.isLiveGalleryTest)
            activeMuseum = selectedMuseum
            startupFailed = false
        } catch {
            model = nil
            startupFailed = true
        }
    }
}

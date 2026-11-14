import SwiftData
import SwiftUI

@main
struct MyApp: App {
    @State private var model: GalleryModel?
    @State private var startupFailed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    ContentView(model: model, translationEnabled: !Self.isUITest)
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
            .task { if model == nil { start() } }
        }
    }

    private static var isUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    private func start() {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: Self.isUITest)
            let container = try ModelContainer(for: StoredArtwork.self, StoredGallery.self, configurations: config)
            var provider: any MuseumAPIProvider = ChicagoAPI()
            var images = ImagePipeline()
            #if DEBUG
            if Self.isUITest {
                let testSession = URLSessionConfiguration.ephemeral
                testSession.protocolClasses = [GalleryFixtureImage.self]
                provider = GalleryFixture()
                images = ImagePipeline(session: URLSession(configuration: testSession))
            }
            #endif
            model = GalleryModel(repository: GalleryStore(container: container, provider: provider), images: images)
            startupFailed = false
        } catch {
            startupFailed = true
        }
    }
}

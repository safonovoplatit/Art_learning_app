import SwiftUI
@preconcurrency import Translation

@MainActor
private struct TranslationService {
    static let source = Locale.Language(identifier: "en")
    static let target = Locale.Language(identifier: "ru")

    func availability() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Self.source, to: Self.target)
    }

    func translate(_ artwork: Artwork, using session: TranslationSession) async throws -> ArtworkTranslation {
        let titles = [
            "The Starry Night": "Звёздная ночь",
            "The Bedroom": "Спальня в Арле",
            "Paris Street; Rainy Day": "Парижская улица в дождливый день",
            "A Sunday on La Grande Jatte — 1884": "Воскресный день на острове Гранд-Жатт — 1884"
        ]
        let title: String
        if let known = titles[artwork.originalTitle] {
            title = known
        } else {
            let sourceTitle = MuseumText.expandingAbbreviations(in: artwork.originalTitle)
            let translated = try await session.translate(sourceTitle).targetText
            let singleParagraph = translated.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            title = singleParagraph.isEmpty ? artwork.originalTitle : singleParagraph
        }
        let sourceAnnotation = MuseumText.expandingAbbreviations(in: artwork.originalDescription)
        let annotation = try await session.translate(sourceAnnotation).targetText
        try Task.checkCancellation()
        return ArtworkTranslation(
            title: title, annotation: annotation, sourceTitle: artwork.originalTitle,
            sourceAnnotation: artwork.originalDescription, sourceLanguage: "en", targetLanguage: "ru",
            version: ArtworkTranslation.currentVersion
        )
    }
}

struct GalleryTranslation: ViewModifier {
    let model: GalleryModel
    private let service = TranslationService()

    @State private var configuration: TranslationSession.Configuration?
    @State private var status: LanguageAvailability.Status?
    @State private var failed = false
    @State private var runID = 0

    func body(content: Content) -> some View {
        content
            .toolbar {
                if model.current?.translation == nil, model.current != nil, status == .supported || failed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(failed ? "Повторить перевод" : "Загрузить перевод", systemImage: "translate") {
                            failed = false
                            begin()
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .task {
                status = await service.availability()
                if status == .installed { begin() }
            }
            .onChange(of: model.artworks.count) { _, _ in
                if status == .installed, !failed, !model.translationCandidates.isEmpty { begin() }
            }
            .translationTask(configuration) { session in
                let activeRun = runID
                do {
                    if status != .installed {
                        try await session.prepareTranslation()
                        try Task.checkCancellation()
                        guard activeRun == runID else { return }
                        status = .installed
                    }
                    while let work = model.translationCandidates.first {
                        try Task.checkCancellation()
                        guard activeRun == runID else { return }
                        let translation = try await service.translate(work, using: session)
                        guard activeRun == runID else { return }
                        try model.apply(translation, to: work.id)
                    }
                } catch {
                    if !Task.isCancelled, activeRun == runID { failed = true }
                }
            }
    }

    private func begin() {
        runID += 1
        if configuration == nil {
            configuration = .init(source: TranslationService.source, target: TranslationService.target)
        } else {
            configuration?.invalidate()
        }
    }
}

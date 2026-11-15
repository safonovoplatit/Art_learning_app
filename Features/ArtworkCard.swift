import SwiftUI

struct ArtworkCard: View {
    let artwork: Artwork
    let width: Int
    let imageHeight: CGFloat
    let model: GalleryModel
    var switchCollection: (() -> Void)?
    let showImage: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var scrollSpace
    @State private var favoriteFeedback = 0

    private let panelOverlap: CGFloat = 24
    private let horizontalPadding: CGFloat = 22
    private let actionSize: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                landscapeCard(columnWidth: geometry.size.width / 2)
            } else {
                portraitCard
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sensoryFeedback(.success, trigger: favoriteFeedback)
    }

    private func landscapeCard(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            artworkImage
                .padding(20)
                .frame(width: columnWidth)
                .frame(maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    cardActions
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    artworkDetails
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .frame(width: columnWidth)
        }
    }

    private var portraitCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: -panelOverlap - actionSize / 2) {
                imageHeader

                artworkDetails
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, actionSize / 2 + 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: panelOverlap,
                            topTrailingRadius: panelOverlap
                        )
                        .fill(Color(uiColor: .systemBackground))
                    }
                    .padding(.top, actionSize / 2)
                    .overlay(alignment: .topTrailing) {
                        cardActions
                            .padding(.trailing, horizontalPadding)
                    }
                    .zIndex(1)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: scrollSpace)
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollIndicators(.hidden)
    }

    private var artworkDetails: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(artwork.title)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("artwork-title")
                Text(artwork.author).font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(artwork.localizedDate ?? String(localized: "Дата неизвестна"))
                Text(location)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(artwork.annotation)
                .font(.body)
                .lineSpacing(5)

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Link(destination: artwork.sourceURL) {
                    Label("Страница произведения", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44, alignment: .leading)
                }
                Text("Изображение: \(artwork.imageRights)")
                Link(artwork.source.displayName, destination: artwork.sourceURL)
                if artwork.translation != nil { Text("Название и аннотация переведены автоматически.") }
                if let credit = artwork.credit { Text(credit) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cardActions: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                actionButtons
            }
        } else {
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            ShareLink(item: artwork.sourceURL) {
                actionLabel {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
            }
            Button {
                let wasFavorite = model.isFavorite(artwork)
                model.toggleFavorite(artwork)
                if !wasFavorite && model.isFavorite(artwork) {
                    favoriteFeedback += 1
                }
            } label: {
                actionLabel {
                    Image(systemName: model.isFavorite(artwork) ? "bookmark.fill" : "bookmark")
                }
            }
            .accessibilityLabel(model.isFavorite(artwork) ? "Удалить из избранного" : "Сохранить в избранное")
            .accessibilityIdentifier("toggle-favorite")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionLabel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let label = content()
            .font(.title3)
            .frame(width: actionSize, height: actionSize)
            .contentShape(Circle())

        if #available(iOS 26, *) {
            label.glassEffect(.regular.interactive(), in: Circle())
        } else {
            label.background(.regularMaterial, in: Circle())
        }
    }

    private var artworkImage: some View {
        ArtworkImage(
            artwork: artwork, width: width, pipeline: model.images,
            open: showImage, offline: model.offline, switchCollection: switchCollection
        )
    }

    private var imageHeader: some View {
        let space = scrollSpace
        let motionReduced = reduceMotion
        return artworkImage
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20 + panelOverlap)
            .frame(height: imageHeight + panelOverlap)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipped()
            .visualEffect { image, geometry in
                let top = geometry.frame(in: .named(space)).minY
                let pull = max(0, top)
                let height = max(1, geometry.size.height)
                let readingOffset = min(max(0, -top) * 0.30, height * 0.30)
                return image
                    .scaleEffect(motionReduced ? 1 : 1 + pull / height, anchor: .top)
                    .offset(y: motionReduced ? 0 : readingOffset - pull)
            }
    }

    private var location: String {
        if artwork.source == .cleveland {
            return String(localized: "Кливлендский музей искусства · Кливленд, США")
        }
        let parts = [artwork.museumName, artwork.city, artwork.country].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Местонахождение неизвестно") : parts.joined(separator: ", ")
    }
}

import SwiftUI

struct ArtworkPager<Card: View>: View {
    let artworks: [Artwork]
    let index: Int
    let select: (Int) -> Void
    @ViewBuilder let card: (Artwork) -> Card

    @State private var visibleID: Artwork.ID?
    @State private var scrollPhase: ScrollPhase = .idle

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(artworks) { artwork in
                        card(artwork)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .accessibilityHidden(artwork.id != selectedID)
                            .id(artwork.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $visibleID, anchor: .leading)
            .onChange(of: selectedID, initial: true) { _, id in
                if visibleID != id { visibleID = id }
            }
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
                if phase == .idle { saveVisibleArtwork() }
            }
            .onChange(of: visibleID) { _, _ in
                if scrollPhase == .idle { saveVisibleArtwork() }
            }
        }
    }

    private var selectedID: Artwork.ID? {
        artworks.indices.contains(index) ? artworks[index].id : nil
    }

    private func saveVisibleArtwork() {
        guard let visibleID, visibleID != selectedID,
              let position = artworks.firstIndex(where: { $0.id == visibleID }) else { return }
        select(position)
    }
}

import SwiftUI

struct ArtworkPager<Card: View>: View {
    let artworks: [Artwork]
    let index: Int
    let select: (Int) -> Void
    @ViewBuilder let card: (Artwork, CGFloat) -> Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation: CGFloat = 0
    @State private var settling = false
    @State private var destination: Int?
    @State private var settledOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let offset = settling ? settledOffset : resisted(translation)
            let neighbors = Array(max(0, index - 1)...min(artworks.count - 1, index + 1))
            ZStack {
                ForEach(neighbors.map { artworks[$0] }) { artwork in
                    if let position = neighbors.first(where: { artworks[$0].id == artwork.id }) {
                        let distance = CGFloat(position - index) * width + offset
                        let parallax = reduceMotion ? 0 : -max(-1, min(1, distance / width)) * 16
                        card(artwork, parallax)
                            .frame(width: width, height: geometry.size.height)
                            .offset(x: distance)
                            .allowsHitTesting(position == index && !settling)
                            .accessibilityHidden(position != index)
                    }
                }
            }
            .frame(width: width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(drag(width: width))
            .onChange(of: index) { _, newValue in
                if destination != newValue { reset() }
            }
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($translation) { value, state, transaction in
                guard !settling, abs(value.translation.width) > abs(value.translation.height) else { return }
                transaction.animation = nil
                state = value.translation.width
            }
            .onEnded { value in
                guard !settling, abs(value.translation.width) > abs(value.translation.height) else { return }
                let direction = Self.direction(
                    distance: value.translation.width,
                    prediction: value.predictedEndTranslation.width,
                    width: width
                )
                let target = index + direction
                let hasTarget = direction != 0 && artworks.indices.contains(target)
                var immediate = Transaction()
                immediate.disablesAnimations = true
                withTransaction(immediate) {
                    settling = true
                    settledOffset = resisted(value.translation.width)
                    destination = hasTarget ? target : nil
                }
                let duration = hasTarget ? 0.35 : 0.24
                let animation: Animation = reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: duration, bounce: 0.08)
                withAnimation(animation, completionCriteria: .logicallyComplete) {
                    settledOffset = hasTarget ? -CGFloat(direction) * width : 0
                } completion: {
                    guard settling else { return }
                    withTransaction(immediate) {
                        if let destination, artworks.indices.contains(destination) { select(destination) }
                        reset()
                    }
                }
            }
    }

    static func direction(distance: CGFloat, prediction: CGFloat, width: CGFloat) -> Int {
        guard abs(distance) >= width * 0.22
                || (abs(distance) >= 18 && distance * prediction > 0 && abs(prediction) >= width * 0.37)
        else { return 0 }
        return distance < 0 ? 1 : -1
    }

    private func resisted(_ distance: CGFloat) -> CGFloat {
        if (index == 0 && distance > 0) || (index == artworks.count - 1 && distance < 0) {
            return distance * 0.20
        }
        return distance
    }

    private func reset() {
        settledOffset = 0
        settling = false
        destination = nil
    }
}

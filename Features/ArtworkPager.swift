import SwiftUI
import UIKit

struct ArtworkPager<Card: View>: View {
    let artworks: [Artwork]
    let index: Int
    let select: (Int) -> Void
    @ViewBuilder let card: (Artwork, CGFloat) -> Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var translation: CGFloat = 0
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
            .gesture(PagerPan { state, distance, velocity in
                switch state {
                case .began, .changed:
                    if !settling { translation = distance }
                case .ended:
                    finish(distance: distance, prediction: distance + velocity * 0.18, width: width)
                case .cancelled, .failed:
                    if !settling { finish(distance: translation, prediction: translation, width: width, cancelled: true) }
                default:
                    break
                }
            })
            .onChange(of: index) { _, newValue in
                if destination != newValue { reset() }
            }
        }
    }

    private func finish(distance: CGFloat, prediction: CGFloat, width: CGFloat, cancelled: Bool = false) {
        guard !settling else { return }
        let direction = cancelled ? 0 : Self.direction(distance: distance, prediction: prediction, width: width)
        let target = index + direction
        let hasTarget = direction != 0 && artworks.indices.contains(target)
        var immediate = Transaction()
        immediate.disablesAnimations = true
        withTransaction(immediate) {
            settling = true
            settledOffset = resisted(distance)
            destination = hasTarget ? target : nil
            translation = 0
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
        translation = 0
        settledOffset = 0
        settling = false
        destination = nil
    }
}


// UIKit arbitrates the horizontal pan against the card's vertical scroll view.
private struct PagerPan: UIGestureRecognizerRepresentable {
    let update: (UIGestureRecognizer.State, CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        update(pan.state, pan.translation(in: pan.view).x, pan.velocity(in: pan.view).x)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}

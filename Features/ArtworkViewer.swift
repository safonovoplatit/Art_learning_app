import SwiftUI
import UIKit

struct ArtworkViewer: View {
    let artwork: Artwork
    let width: Int
    let pipeline: ImagePipeline
    @Environment(\.dismiss) private var dismiss
    @State private var picture: UIImage?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let picture {
                    ZoomableImage(image: picture, zoomable: artwork.isZoomable, title: artwork.title)
                        .ignoresSafeArea(edges: .bottom)
                } else if failed {
                    VStack(spacing: 12) {
                        Text("Изображение недоступно")
                        Button("Повторить") { retry += 1 }.buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Button("Закрыть", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.75), in: Circle())
                .padding(12)
                .accessibilityIdentifier("close-artwork")
        }
        .preferredColorScheme(.dark)
        .task(id: retry) {
            failed = false
            for rendition in (artwork.isZoomable ? [width, 843] : [843, width]).uniqued {
                if let image = try? await pipeline.image(artwork.imageURL(width: rendition), pixels: rendition * 3 / 2, fallback: artwork.fallbackImageURL(width: rendition)),
                   !Task.isCancelled {
                    picture = image
                    break
                }
            }
            if artwork.isZoomable,
               let large = try? await pipeline.image(artwork.imageURL(width: 1800), pixels: 2200, fallback: artwork.fallbackImageURL(width: 1800)),
               !Task.isCancelled {
                picture = large
            }
            if !Task.isCancelled { failed = picture == nil }
        }
    }
}

private extension Array where Element == Int {
    var uniqued: [Int] { reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let zoomable: Bool
    let title: String

    func makeUIView(context: Context) -> ZoomScrollView { ZoomScrollView() }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.update(image: image, zoomable: zoomable, title: title)
    }
}

private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let artwork = UIImageView()
    private var lastSize = CGSize.zero
    private var dirty = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        artwork.contentMode = .scaleAspectFit
        artwork.isAccessibilityElement = true
        artwork.accessibilityTraits = .image
        addSubview(artwork)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { nil }

    func update(image: UIImage, zoomable: Bool, title: String) {
        let nextMaximum: CGFloat = zoomable ? 4 : 1
        if artwork.image !== image {
            let previous = artwork.image?.size ?? .zero
            artwork.image = image
            let oldRatio = previous.height > 0 ? previous.width / previous.height : 0
            let ratio = image.size.width / max(1, image.size.height)
            if abs(oldRatio - ratio) > 0.02 { dirty = true }
        }
        maximumZoomScale = nextMaximum
        artwork.accessibilityLabel = title
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let size = artwork.image?.size, bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != lastSize || dirty {
            lastSize = bounds.size
            dirty = false
            setZoomScale(1, animated: false)
            let fit = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * fit, height: size.height * fit)
            artwork.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { artwork }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != insets { contentInset = insets }
    }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        guard maximumZoomScale > 1 else { return }
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            let point = tap.location(in: artwork)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}

import SwiftUI
import UIKit

struct NativeImageViewer: View {
    let images: [DynamicImageItem]
    let initialIndex: Int
    let transitionID: String
    let transitionNamespace: Namespace.ID
    let hidesRootTabBarDuringPresentation: Bool
    let usesZoomTransition: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var isClosing = false
    @State private var dragOffset: CGSize = .zero

    init(
        images: [DynamicImageItem],
        initialIndex: Int,
        transitionID: String,
        transitionNamespace: Namespace.ID,
        hidesRootTabBarDuringPresentation: Bool = true,
        usesZoomTransition: Bool = false
    ) {
        self.images = images
        self.initialIndex = initialIndex
        self.transitionID = transitionID
        self.transitionNamespace = transitionNamespace
        self.hidesRootTabBarDuringPresentation = hidesRootTabBarDuringPresentation
        self.usesZoomTransition = usesZoomTransition
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    RemoteZoomableImage(image: image) {
                        closeViewer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            .offset(dragOffset)
            .scaleEffect(dragScale)

            if images.count > 1 && !isClosing {
                Text("\(selection + 1) / \(images.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 22)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dismissDragGesture)
        .background(Color.black.ignoresSafeArea())
        .presentationBackground(.black)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .nativeImageViewerNavigationTransition(
            usesZoomTransition,
            sourceID: transitionID,
            namespace: transitionNamespace
        )
        .nativeImageViewerPresentationTabBarHider(hidesRootTabBarDuringPresentation)
    }

    private var backgroundOpacity: Double {
        let progress = min(max(abs(dragOffset.height) / 320, 0), 0.82)
        return 1 - progress
    }

    private var dragScale: CGFloat {
        let progress = min(max(abs(dragOffset.height) / 520, 0), 0.16)
        return 1 - progress
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard !isClosing else { return }
                let translation = value.translation
                guard abs(translation.height) > abs(translation.width) * 1.12 else { return }
                dragOffset = CGSize(
                    width: translation.width * 0.22,
                    height: translation.height
                )
            }
            .onEnded { value in
                guard !isClosing else { return }
                let predicted = value.predictedEndTranslation.height
                let shouldClose = abs(value.translation.height) > 118 || abs(predicted) > 210
                if shouldClose {
                    closeViewer()
                } else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func closeViewer() {
        guard !isClosing else { return }
        isClosing = true
        dismiss()
    }
}

private extension View {
    @ViewBuilder
    func nativeImageViewerNavigationTransition(
        _ isEnabled: Bool,
        sourceID: String,
        namespace: Namespace.ID
    ) -> some View {
        if isEnabled {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    @ViewBuilder
    func nativeImageViewerPresentationTabBarHider(_ isEnabled: Bool) -> some View {
        if isEnabled {
            keepsRootTabBarHiddenDuringPresentation()
        } else {
            self
        }
    }
}

enum NativeImageViewerTransitionID {
    static func image(_ image: DynamicImageItem, index: Int, scope: String) -> String {
        let source = image.normalizedURL ?? image.url
        return "\(scope)|\(index)|\(source)"
    }
}

private struct RemoteZoomableImage: View {
    let image: DynamicImageItem
    let close: () -> Void
    @StateObject private var loader = CachedRemoteImageLoader()

    private var imageURL: URL? {
        image.normalizedURL
            .map { $0.biliImageThumbnailURL(maxSide: 2600) }
            .flatMap(URL.init(string:))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                ZoomableUIImageView(image: image, onSingleTap: close)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .task(id: imageURL?.absoluteString ?? "") {
            await loader.load(url: imageURL, scale: UIScreen.main.scale, targetPixelSize: 2600)
        }
        .onDisappear {
            loader.cancel()
            if loader.image == nil {
                loader.reset()
            }
        }
    }
}

private struct ZoomableUIImageView: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        guard context.coordinator.imageView?.image !== image else { return }
        context.coordinator.imageView?.image = image
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onSingleTap: () -> Void
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let location = recognizer.location(in: imageView)
            let targetScale = min(scrollView.maximumZoomScale, 2.6)
            let width = scrollView.bounds.width / targetScale
            let height = scrollView.bounds.height / targetScale
            let rect = CGRect(
                x: location.x - width / 2,
                y: location.y - height / 2,
                width: width,
                height: height
            )
            scrollView.zoom(to: rect, animated: true)
        }
    }
}

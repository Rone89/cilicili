import Combine
import SwiftUI
import UIKit

struct ZoomyFullScreenImageViewer: View {
    let initialImage: UIImage?
    let url: URL?
    let items: [ZoomyImagePreviewItem]
    let initialItemID: String
    let viewerGroup: ZoomyImagePreviewGroup?
    let targetPixelSize: Int
    let onSelectedItemChanged: (ZoomyImagePreviewItem, UIImage?) -> Void
    let onDismissDragChanged: (CGFloat) -> Void
    let onImageUpdated: (UIImage) -> Void
    @Binding var isPresented: Bool
    @State private var selectedItemID: String
    @State private var dismissDragOffset: CGFloat = 0

    init(
        initialImage: UIImage?,
        url: URL?,
        items: [ZoomyImagePreviewItem],
        initialItemID: String,
        viewerGroup: ZoomyImagePreviewGroup?,
        targetPixelSize: Int,
        isPresented: Binding<Bool>,
        onSelectedItemChanged: @escaping (ZoomyImagePreviewItem, UIImage?) -> Void,
        onDismissDragChanged: @escaping (CGFloat) -> Void,
        onImageUpdated: @escaping (UIImage) -> Void
    ) {
        self.initialImage = initialImage
        self.url = url
        self.items = items
        self.initialItemID = initialItemID
        self.viewerGroup = viewerGroup
        self.targetPixelSize = targetPixelSize
        self.onSelectedItemChanged = onSelectedItemChanged
        self.onDismissDragChanged = onDismissDragChanged
        self.onImageUpdated = onImageUpdated
        _isPresented = isPresented
        _selectedItemID = State(initialValue: initialItemID)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZStack {
                if items.count > 1 {
                    TabView(selection: $selectedItemID) {
                        ForEach(items) { item in
                            imagePage(for: item)
                                .tag(item.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .ignoresSafeArea()
                } else {
                    imagePage(for: items.first)
                        .ignoresSafeArea()
                }

                viewerChrome
            }
            .offset(y: dismissDragOffset)
        }
        .simultaneousGesture(dismissDragGesture)
        .onAppear {
            syncSelectedItemContext()
            prewarmNeighborImages()
        }
        .onChange(of: selectedItemID) { _, _ in
            syncSelectedItemContext()
            prewarmNeighborImages()
        }
        .statusBarHidden(true)
        .accessibilityLabel("图片预览")
    }

    private var backgroundOpacity: Double {
        let progress = min(max(abs(dismissDragOffset) / 260, 0), 1)
        return 1 - progress * 0.45
    }

    private var chromeOpacity: Double {
        let progress = min(max(abs(dismissDragOffset) / 180, 0), 1)
        return 1 - progress * 0.6
    }

    private var viewerChrome: some View {
        ZStack(alignment: .top) {
            if items.count > 1 {
                Text(counterText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.black.opacity(0.46), in: Capsule())
                    .allowsHitTesting(false)
            }

        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(chromeOpacity)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let verticalTravel = value.translation.height
                let horizontalTravel = abs(value.translation.width)
                guard verticalTravel > 0, verticalTravel > horizontalTravel * 1.15 else { return }
                dismissDragOffset = verticalTravel
                onDismissDragChanged(verticalTravel)
            }
            .onEnded { value in
                let verticalTravel = value.translation.height
                let horizontalTravel = abs(value.translation.width)
                let predictedTravel = value.predictedEndTranslation.height
                guard verticalTravel > 0, verticalTravel > horizontalTravel * 1.15 else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                        dismissDragOffset = 0
                        onDismissDragChanged(0)
                    }
                    return
                }
                if verticalTravel > 120 || predictedTravel > 220 {
                    onDismissDragChanged(verticalTravel)
                    isPresented = false
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                        dismissDragOffset = 0
                        onDismissDragChanged(0)
                    }
                }
            }
    }

    @ViewBuilder
    private func imagePage(for item: ZoomyImagePreviewItem?) -> some View {
        if let item {
            ZoomyViewerImagePage(
                item: item,
                initialImage: initialImage(for: item),
                targetPixelSize: targetPixelSize,
                isPresented: $isPresented,
                onImageUpdated: { itemID, image in
                    viewerGroup?.setImage(image, for: itemID)
                    if itemID == selectedItemID {
                        onImageUpdated(image)
                    }
                }
            )
        } else if let url {
            ZoomyViewerImagePage(
                item: ZoomyImagePreviewItem(id: url.absoluteString, viewerURL: url),
                initialImage: initialImage,
                targetPixelSize: targetPixelSize,
                isPresented: $isPresented,
                onImageUpdated: { _, image in
                    onImageUpdated(image)
                }
            )
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selectedItemID } ?? 0
    }

    private var counterText: String {
        "\(selectedIndex + 1)/\(max(items.count, 1))"
    }

    private func initialImage(for item: ZoomyImagePreviewItem) -> UIImage? {
        if item.id == initialItemID {
            return initialImage ?? viewerGroup?.image(for: item.id)
        }
        return viewerGroup?.image(for: item.id)
    }

    private func syncSelectedItemContext() {
        guard let item = items.first(where: { $0.id == selectedItemID }) else { return }
        let cachedImage = viewerGroup?.image(for: item.id)
        onSelectedItemChanged(item, cachedImage)
        if let cachedImage {
            onImageUpdated(cachedImage)
        }
    }

    private func prewarmNeighborImages() {
        guard items.count > 1 else { return }
        let neighborIndices = [selectedIndex - 1, selectedIndex + 1]
        let sources = neighborIndices.compactMap { index -> RemoteImageSource? in
            guard items.indices.contains(index),
                  let url = items[index].displayURL
            else { return nil }
            return RemoteImageSource(url: url)
        }
        guard !sources.isEmpty else { return }
        Task(priority: .utility) {
            await RemoteImageCache.shared.prefetch(
                sources,
                targetPixelSize: targetPixelSize,
                maximumConcurrentLoads: 2
            )
        }
    }

    func cancelLoading() {
    }
}

private struct ZoomyViewerImagePage: View {
    let item: ZoomyImagePreviewItem
    let initialImage: UIImage?
    let targetPixelSize: Int
    @Binding var isPresented: Bool
    let onImageUpdated: (String, UIImage) -> Void
    @StateObject private var loader: ZoomyViewerImageLoader

    init(
        item: ZoomyImagePreviewItem,
        initialImage: UIImage?,
        targetPixelSize: Int,
        isPresented: Binding<Bool>,
        onImageUpdated: @escaping (String, UIImage) -> Void
    ) {
        self.item = item
        self.initialImage = initialImage
        self.targetPixelSize = targetPixelSize
        _isPresented = isPresented
        self.onImageUpdated = onImageUpdated
        _loader = StateObject(wrappedValue: ZoomyViewerImageLoader(initialImage: initialImage))
    }

    var body: some View {
        ZStack {
            if let image = loader.image {
                ZoomyZoomableImageView(image: image) {
                    isPresented = false
                }
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.displayURL?.absoluteString ?? item.id) {
            await loader.load(url: item.displayURL, targetPixelSize: targetPixelSize)
        }
        .onAppear {
            if let image = loader.image {
                onImageUpdated(item.id, image)
            }
        }
        .onChange(of: loader.image) { _, image in
            if let image {
                onImageUpdated(item.id, image)
            }
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

@MainActor
private final class ZoomyViewerImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var task: Task<Void, Never>?

    init(initialImage: UIImage?) {
        image = initialImage
    }

    func load(url: URL?, targetPixelSize: Int) async {
        task?.cancel()
        guard let url else { return }

        task = Task(priority: .userInitiated) { [weak self] in
            if let cachedImage = await RemoteImageCache.shared.image(for: url, scale: 1, targetPixelSize: targetPixelSize) {
                await MainActor.run {
                    self?.image = cachedImage
                }
                return
            }

            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            guard let loadedImage = await RemoteImageCache.shared.load(
                url: url,
                scale: 1,
                targetPixelSize: targetPixelSize
            ),
                !Task.isCancelled
            else { return }

            await MainActor.run {
                self?.image = loadedImage
            }
        }
        await task?.value
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

private struct ZoomyZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onTapExit: () -> Void

    func makeUIView(context _: Context) -> ZoomyZoomableImageHostView {
        let view = ZoomyZoomableImageHostView()
        view.onTapExit = onTapExit
        return view
    }

    func updateUIView(_ view: ZoomyZoomableImageHostView, context _: Context) {
        view.onTapExit = onTapExit
        view.setImage(image)
    }
}

private final class ZoomyZoomableImageHostView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onTapExit: (() -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var currentImageIdentifier: ObjectIdentifier?
    private var lastLayoutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        scrollView.addSubview(imageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tap.numberOfTapsRequired = 1
        tap.delegate = self

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        tap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(doubleTap)
        scrollView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        let identifier = ObjectIdentifier(image)
        guard currentImageIdentifier != identifier else { return }
        currentImageIdentifier = identifier
        imageView.image = image
        resetZoomLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.size != lastLayoutSize else {
            centerImage()
            return
        }
        lastLayoutSize = bounds.size
        resetZoomLayout()
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerImage()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer
    }

    @objc private func handleSingleTap() {
        onTapExit?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        let targetScale: CGFloat
        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
            targetScale = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale * 2.4, 2.4))
        } else {
            targetScale = scrollView.minimumZoomScale
        }

        if targetScale <= scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = recognizer.location(in: imageView)
            scrollView.zoom(to: zoomRect(for: targetScale, centeredAt: location), animated: true)
        }
    }

    private func resetZoomLayout() {
        guard let image = imageView.image,
              bounds.width > 1,
              bounds.height > 1,
              image.size.width > 0,
              image.size.height > 0
        else { return }

        scrollView.zoomScale = 1
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5

        let fittedSize = aspectFitSize(imageSize: image.size, boundsSize: bounds.size)
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize
        centerImage()
    }

    private func centerImage() {
        let horizontalInset = max((bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let verticalInset = max((bounds.height - scrollView.contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func aspectFitSize(imageSize: CGSize, boundsSize: CGSize) -> CGSize {
        let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    private func zoomRect(for scale: CGFloat, centeredAt center: CGPoint) -> CGRect {
        let width = scrollView.bounds.width / scale
        let height = scrollView.bounds.height / scale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }
}

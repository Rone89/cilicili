import SwiftUI
import UIKit

struct NativeImageViewer: View {
    let images: [DynamicImageItem]
    let initialIndex: Int
    let transitionID: String
    let transitionNamespace: Namespace.ID
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var isClosing = false

    init(
        images: [DynamicImageItem],
        initialIndex: Int,
        transitionID: String,
        transitionNamespace: Namespace.ID
    ) {
        self.images = images
        self.initialIndex = initialIndex
        self.transitionID = transitionID
        self.transitionNamespace = transitionNamespace
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
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

            if images.count > 1 {
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
        .background(Color.black.ignoresSafeArea())
        .presentationBackground(.black)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .navigationTransition(.zoom(sourceID: transitionID, in: transitionNamespace))
        .background(NativeImageViewerChromeLock())
    }

    private func closeViewer() {
        guard !isClosing else { return }
        isClosing = true
        dismiss()
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

private struct NativeImageViewerChromeLock: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.lockChrome()
    }

    final class Controller: UIViewController {
        private var didLockChrome = false

        override func loadView() {
            view = PassthroughView()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            lockChrome()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            lockChrome()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            unlockChromeAfterDismissal()
        }

        func lockChrome() {
            if didLockChrome {
                NativeImageViewerChromeLockStore.shared.hideCapturedChrome()
                return
            }

            didLockChrome = true
            NativeImageViewerChromeLockStore.shared.lock(from: self)
        }

        private func unlockChromeAfterDismissal() {
            guard didLockChrome else { return }
            didLockChrome = false
            NativeImageViewerChromeLockStore.shared.unlockAfterDismissal()
        }
    }

    private final class PassthroughView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

@MainActor
private final class NativeImageViewerChromeLockStore {
    static let shared = NativeImageViewerChromeLockStore()

    private var navigationStates: [ObjectIdentifier: NavigationState] = [:]
    private var tabStates: [ObjectIdentifier: TabState] = [:]
    private var unlockWorkItem: DispatchWorkItem?

    func lock(from controller: UIViewController) {
        unlockWorkItem?.cancel()
        unlockWorkItem = nil

        if navigationStates.isEmpty && tabStates.isEmpty {
            captureChrome(from: controller)
        }

        hideCapturedChrome()
    }

    func hideCapturedChrome() {
        navigationStates.values.forEach { state in
            state.controller?.navigationBar.alpha = 0
        }
        tabStates.values.forEach { state in
            state.controller?.tabBar.alpha = 0
        }
    }

    func unlockAfterDismissal() {
        unlockWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreChrome()
        }
        unlockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: workItem)
    }

    private func captureChrome(from controller: UIViewController) {
        var roots = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.isKeyWindow || !$0.isHidden }
            .compactMap(\.rootViewController)

        if let presenting = controller.presentingViewController {
            roots.append(presenting)
        }
        roots.append(controller)

        var navigationControllers: [UINavigationController] = []
        var tabControllers: [UITabBarController] = []

        for root in roots {
            collectChromeControllers(
                from: root,
                navigationControllers: &navigationControllers,
                tabControllers: &tabControllers
            )
        }

        for navigationController in navigationControllers {
            let id = ObjectIdentifier(navigationController)
            navigationStates[id] = NavigationState(
                controller: navigationController,
                navigationBarAlpha: navigationController.navigationBar.alpha
            )
        }

        for tabController in tabControllers {
            let id = ObjectIdentifier(tabController)
            tabStates[id] = TabState(
                controller: tabController,
                tabBarAlpha: tabController.tabBar.alpha
            )
        }
    }

    private func collectChromeControllers(
        from controller: UIViewController,
        navigationControllers: inout [UINavigationController],
        tabControllers: inout [UITabBarController]
    ) {
        if let navigationController = controller as? UINavigationController {
            navigationControllers.append(navigationController)
        }

        if let tabController = controller as? UITabBarController {
            tabControllers.append(tabController)
        }

        for child in controller.children {
            collectChromeControllers(
                from: child,
                navigationControllers: &navigationControllers,
                tabControllers: &tabControllers
            )
        }

        if let presented = controller.presentedViewController {
            collectChromeControllers(
                from: presented,
                navigationControllers: &navigationControllers,
                tabControllers: &tabControllers
            )
        }
    }

    private func restoreChrome() {
        navigationStates.values.forEach { state in
            state.controller?.navigationBar.alpha = state.navigationBarAlpha
        }

        tabStates.values.forEach { state in
            state.controller?.tabBar.alpha = state.tabBarAlpha
        }

        navigationStates.removeAll()
        tabStates.removeAll()
        unlockWorkItem = nil
    }

    private final class NavigationState {
        weak var controller: UINavigationController?
        let navigationBarAlpha: CGFloat

        init(controller: UINavigationController, navigationBarAlpha: CGFloat) {
            self.controller = controller
            self.navigationBarAlpha = navigationBarAlpha
        }
    }

    private final class TabState {
        weak var controller: UITabBarController?
        let tabBarAlpha: CGFloat

        init(controller: UITabBarController, tabBarAlpha: CGFloat) {
            self.controller = controller
            self.tabBarAlpha = tabBarAlpha
        }
    }
}

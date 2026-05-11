import SwiftUI
import Combine
import UIKit

struct HomeView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject private var viewModel: HomeViewModel
    let autoOpenDetail: Bool
    let startVideo: VideoItem?
    @Binding var detailPath: NavigationPath
    let onVideoSelect: ((VideoItem) -> Void)?
    @State private var didAutoOpenDetail = false
    @State private var pullDistance: CGFloat = 0

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        viewModel: HomeViewModel,
        autoOpenDetail: Bool,
        startVideo: VideoItem?,
        detailPath: Binding<NavigationPath>,
        onVideoSelect: ((VideoItem) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.autoOpenDetail = autoOpenDetail
        self.startVideo = startVideo
        _detailPath = detailPath
        self.onVideoSelect = onVideoSelect
    }

    var body: some View {
        content(viewModel)
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.large)
        .nativeTopNavigationChrome()
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        videoFeed(viewModel)
            .id(viewModel.mode)
            .transition(feedTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.smooth(duration: 0.26), value: viewModel.mode)
        .task {
            await viewModel.loadInitial()
            openFirstDetailIfNeeded(viewModel)
        }
        .onChange(of: viewModel.videos.first?.id) { _, _ in
            openFirstDetailIfNeeded(viewModel)
        }
    }

    private func feedPicker(_ viewModel: HomeViewModel) -> some View {
        Picker("Feed", selection: Binding(
            get: { viewModel.mode },
            set: { newMode in
                Task { await viewModel.switchMode(newMode) }
            }
        )) {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private func feedPickerRow(_ viewModel: HomeViewModel) -> some View {
        feedPicker(viewModel)
            .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private var feedTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .trailing))
    }

    @ViewBuilder
    private func videoFeed(_ viewModel: HomeViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                refreshBridge(viewModel)

                feedPickerRow(viewModel)

                if viewModel.videos.isEmpty && viewModel.state.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载\(viewModel.mode.title)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else if viewModel.videos.isEmpty {
                    EmptyStateView(
                        title: "暂无内容",
                        systemImage: "play.rectangle",
                        message: "下拉刷新或切换频道再试。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(viewModel.videos) { video in
                            videoCard(video)
                            .task {
                                await viewModel.loadMoreIfNeeded(current: video)
                                await viewModel.loadAuthorAvatarIfNeeded(for: video)
                                await viewModel.preloadPlaybackIfUseful(for: video)
                            }
                            .onDisappear {
                                Task {
                                    await viewModel.cancelPlaybackPreload(for: video)
                                }
                            }
                        }

                        if viewModel.state.isLoading && !viewModel.isRefreshing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .gridCellColumns(2)
                                .padding()
                        }
                    }
                    .padding(.horizontal, 10)
                    .id(viewModel.feedContentVersion)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity
                    ))
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .animation(.smooth(duration: 0.28), value: viewModel.feedContentVersion)
        .overlay(alignment: .top) {
            pullRefreshIndicator
        }
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.videos.isEmpty {
                ErrorStateView(title: "加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
            }
        }
    }

    private func refreshBridge(_ viewModel: HomeViewModel) -> some View {
        HomeScrollRefreshBridge(
            isRefreshing: viewModel.isRefreshing,
            triggerDistance: CGFloat(libraryStore.homeRefreshTriggerDistance),
            onPullDistanceChange: { distance in
                pullDistance = distance
            },
            onRefresh: {
                Task {
                    await viewModel.refreshFromUserPull()
                }
            }
        )
        .frame(height: 0)
    }

    @ViewBuilder
    private var pullRefreshIndicator: some View {
        let triggerDistance = CGFloat(libraryStore.homeRefreshTriggerDistance)
        let progress = min(max(pullDistance / max(triggerDistance, 1), 0), 1)
        if pullDistance > 14 || viewModel.isRefreshing {
            ProgressView()
                .scaleEffect(0.82 + progress * 0.18)
                .opacity(viewModel.isRefreshing ? 1 : progress)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .padding(.top, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private func videoCard(_ video: VideoItem) -> some View {
        if let onVideoSelect {
            Button {
                onVideoSelect(video)
            } label: {
                VideoCardView(video: video)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: video) {
                VideoCardView(video: video)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .buttonStyle(.plain)
        }
    }

    private func openFirstDetailIfNeeded(_ viewModel: HomeViewModel) {
        guard autoOpenDetail,
              !didAutoOpenDetail,
              detailPath.isEmpty else {
            return
        }

        let video = startVideo ?? viewModel.videos.first
        guard let video else { return }
        didAutoOpenDetail = true
        if let onVideoSelect {
            onVideoSelect(video)
        } else {
            detailPath.append(video)
        }
    }
}

private struct HomeScrollRefreshBridge: UIViewRepresentable {
    let isRefreshing: Bool
    let triggerDistance: CGFloat
    let onPullDistanceChange: (CGFloat) -> Void
    let onRefresh: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isRefreshing: isRefreshing,
            triggerDistance: triggerDistance,
            onPullDistanceChange: onPullDistanceChange,
            onRefresh: onRefresh
        )
    }

    func makeUIView(context: Context) -> RefreshProbeView {
        let view = RefreshProbeView()
        view.onMoveToWindow = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.attach(from: view)
        }
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }
            coordinator?.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: RefreshProbeView, context: Context) {
        let wasRefreshing = context.coordinator.isRefreshing
        context.coordinator.isRefreshing = isRefreshing
        context.coordinator.triggerDistance = triggerDistance
        context.coordinator.onPullDistanceChange = onPullDistanceChange
        context.coordinator.onRefresh = onRefresh
        if wasRefreshing, !isRefreshing {
            context.coordinator.finishRefreshing()
        }
        DispatchQueue.main.async { [weak uiView, weak coordinator = context.coordinator] in
            guard let uiView else { return }
            coordinator?.attach(from: uiView)
        }
    }

    final class Coordinator: NSObject {
        var isRefreshing: Bool
        var triggerDistance: CGFloat
        var onPullDistanceChange: (CGFloat) -> Void
        var onRefresh: () -> Void

        private weak var scrollView: UIScrollView?
        private var contentOffsetObservation: NSKeyValueObservation?
        private var didTriggerRefresh = false

        init(
            isRefreshing: Bool,
            triggerDistance: CGFloat,
            onPullDistanceChange: @escaping (CGFloat) -> Void,
            onRefresh: @escaping () -> Void
        ) {
            self.isRefreshing = isRefreshing
            self.triggerDistance = triggerDistance
            self.onPullDistanceChange = onPullDistanceChange
            self.onRefresh = onRefresh
            super.init()
        }

        deinit {
            contentOffsetObservation?.invalidate()
        }

        func attach(from view: UIView) {
            guard let foundScrollView = view.enclosingScrollView(),
                  scrollView !== foundScrollView
            else {
                return
            }

            contentOffsetObservation?.invalidate()
            scrollView = foundScrollView
            foundScrollView.alwaysBounceVertical = true
            foundScrollView.refreshControl = nil

            contentOffsetObservation = foundScrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                Task { @MainActor [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.handleScroll(scrollView)
                }
            }
        }

        func finishRefreshing() {
            guard let scrollView else {
                didTriggerRefresh = false
                onPullDistanceChange(0)
                return
            }

            let distance = max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
            guard distance < 12, !scrollView.isDragging else { return }
            didTriggerRefresh = false
            onPullDistanceChange(0)
        }

        private func handleScroll(_ scrollView: UIScrollView) {
            let distance = max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
            onPullDistanceChange(distance)

            guard !isRefreshing else { return }

            if distance < 12, !scrollView.isDragging {
                didTriggerRefresh = false
                onPullDistanceChange(0)
                return
            }

            guard distance >= triggerDistance,
                  scrollView.isDragging,
                  !didTriggerRefresh
            else { return }

            didTriggerRefresh = true
            onRefresh()
        }
    }
}

private final class RefreshProbeView: UIView {
    var onMoveToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMoveToWindow?()
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

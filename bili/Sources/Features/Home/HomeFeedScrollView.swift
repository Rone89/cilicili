import SwiftUI
import UIKit

private enum HomeFeedScrollAnchor {
    static let top = "home-feed-top"
}

enum HomeNativeRefreshLayout {
    static let revealDistance: CGFloat = 44

    static func targetOffsetY(restingTopOffsetY: CGFloat) -> CGFloat {
        restingTopOffsetY - revealDistance
    }
}

struct HomeFeedScrollView<FeedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: HomeViewModel
    @Binding var viewportState: HomeFeedViewportState
    @ObservedObject var scrollActions: HomeFeedScrollActions
    let nativeRefreshActionStore: HomeNativeRefreshActionStore
    let layout: HomeFeedLayout
    @ViewBuilder let feedContent: () -> FeedContent

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    HomeFeedScrollContent(
                        isShowingInitialPlaceholder: viewModel.videos.isEmpty && (viewModel.state == .idle || viewModel.state.isLoading),
                        isEmpty: viewModel.videos.isEmpty,
                        mode: viewModel.mode,
                        feedContent: feedContent
                    )
                }
                .id(HomeFeedScrollAnchor.top)
                .background {
                    HomeFeedWidthReader()
                }
                .background {
                    HomeNativeRefreshControlTrigger(
                        requestID: scrollActions.programmaticRefreshRequestID,
                        action: viewModel.refreshFromUserPull
                    )
                    .frame(width: 0, height: 0)
                }
                .background {
                    HomeNativeRefreshActionReader(
                        store: nativeRefreshActionStore
                    )
                }
                .background {
                    HomeScrollsToTopBehavior(
                        isEnabled: true
                    )
                    .frame(width: 0, height: 0)
                }
            }
            .rootFloatingTabBarContentPadding()
            .contentMargins(.top, 0, for: .scrollContent)
            .background(HomeViewportHeightReader())
            .homeFeedScrollPreferenceHandling(
                viewportState: $viewportState,
                scrollActions: scrollActions
            )
            .refreshable(action: viewModel.refreshFromUserPull)
            .scrollBounceBehavior(.always, axes: .vertical)
            .defersRemoteImageLoadsDuringFastScroll()
            .background(layout.homeFeedBackground)
            .nativeTopScrollEdgeEffect()
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: layout)
            .homeFeedScrollOverlays(
                viewModel: viewModel
            )
            .onChange(of: scrollActions.topScrollRequestID) { _, _ in
                scrollToTop(proxy)
            }
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(HomeFeedScrollAnchor.top, anchor: .top)
        } else {
            withAnimation(.smooth(duration: 0.34)) {
                proxy.scrollTo(HomeFeedScrollAnchor.top, anchor: .top)
            }
        }
    }
}

private struct HomeScrollsToTopBehavior: UIViewRepresentable {
    let isEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            view?.enclosingScrollView?.scrollsToTop = isEnabled
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        view.enclosingScrollView?.scrollsToTop = true
    }
}

private struct HomeNativeRefreshActionReader: View {
    @Environment(\.refresh) private var refreshAction
    let store: HomeNativeRefreshActionStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                store.action = refreshAction
            }
            .onDisappear {
                store.action = nil
            }
    }
}

private struct HomeNativeRefreshControlTrigger: UIViewRepresentable {
    let requestID: Int
    let action: @MainActor () async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.update(
            requestID: requestID,
            sourceView: view,
            action: action
        )
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    @MainActor
    final class Coordinator {
        private var lastRequestID = 0
        private var refreshTask: Task<Void, Never>?

        func update(
            requestID: Int,
            sourceView: UIView,
            action: @escaping @MainActor () async -> Void
        ) {
            guard requestID != lastRequestID else { return }
            lastRequestID = requestID
            guard requestID > 0, refreshTask == nil else { return }

            refreshTask = Task { @MainActor [weak self, weak sourceView] in
                defer { self?.refreshTask = nil }
                guard let sourceView,
                      let scrollView = await self?.findScrollView(from: sourceView),
                      let refreshControl = scrollView.refreshControl
                else { return }

                let restingTopOffsetY = -scrollView.adjustedContentInset.top
                refreshControl.beginRefreshing()
                scrollView.layoutIfNeeded()
                let targetOffset = CGPoint(
                    x: scrollView.contentOffset.x,
                    y: HomeNativeRefreshLayout.targetOffsetY(
                        restingTopOffsetY: restingTopOffsetY
                    )
                )
                scrollView.setContentOffset(targetOffset, animated: true)

                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else {
                    refreshControl.endRefreshing()
                    return
                }
                await action()
                refreshControl.endRefreshing()
            }
        }

        func cancel() {
            refreshTask?.cancel()
            refreshTask = nil
        }

        private func findScrollView(from sourceView: UIView) async -> UIScrollView? {
            for _ in 0..<8 {
                if let scrollView = sourceView.enclosingScrollView {
                    return scrollView
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
            return nil
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var currentView = superview
        while let view = currentView {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }
}

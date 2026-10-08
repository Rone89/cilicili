import SwiftUI

struct HomeFeedScreenBody: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var runtimeSettings: HomeRuntimeSettingsStore
    @ObservedObject var libraryStore: LibraryStore
    @Binding var viewportState: HomeFeedViewportState
    @Binding var detailPath: NavigationPath
    let contentActions: HomeFeedContentActions
    let actionStore: HomeFeedScreenActionStore
    let launchConfiguration: HomeFeedLaunchConfiguration

    var body: some View {
        let layout = effectiveLayout
        let layoutMetrics = viewportState.layoutMetrics(
            for: layout,
            standardHorizontalInset: libraryStore.standardPageHorizontalInset
        )
        let imagePrefetchProfile = HomeFeedCoverPrefetchProfile.make(
            layout: layout,
            metrics: layoutMetrics,
            displayScale: displayScale
        )

        HomeFeedScrollView(
            viewModel: viewModel,
            viewportState: $viewportState,
            scrollActions: actionStore.scroll,
            nativeRefreshActionStore: actionStore.nativeRefresh,
            layout: layout
        ) {
            HomeFeedContentSection(
                metrics: layoutMetrics,
                cells: viewModel.videoCells,
                lastSeenMarkerIndex: viewModel.lastSeenMarkerIndex,
                isLoadingMore: viewModel.state.isLoading && !viewModel.isRefreshing && !viewModel.isUserRefreshing,
                actions: contentActions
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: imagePrefetchProfile.cacheIdentity) {
            viewModel.updateImagePrefetchProfile(imagePrefetchProfile)
        }
        .background(layout.homeFeedBackground)
        .overlay(alignment: .top) {
            if let notice = viewModel.recommendationFeedbackNotice {
                HomeRecommendationFeedbackNoticeView(notice: notice)
                    .accessibilityIdentifier("home.recommendation.feedbackMessage")
            }
        }
        .task(id: viewModel.recommendationFeedbackNotice) {
            guard viewModel.recommendationFeedbackNotice != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            viewModel.recommendationFeedbackNotice = nil
        }
        .homeFeedScreenLifecycle(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            libraryStore: libraryStore,
            detailPath: $detailPath,
            configuration: lifecycleConfiguration
        )
    }

    private var effectiveLayout: HomeFeedLayout {
        guard dynamicTypeSize.isAccessibilitySize else {
            return runtimeSettings.homeFeedLayout
        }

        switch runtimeSettings.homeFeedLayout {
        case .doubleColumn, .borderedDoubleColumn:
            return .singleColumn
        case .singleColumn, .borderedSingleColumn:
            return runtimeSettings.homeFeedLayout
        }
    }

    private var lifecycleConfiguration: HomeFeedScreenLifecycleConfiguration {
        HomeFeedScreenLifecycleConfiguration(
            launchConfiguration: launchConfiguration,
            lifecycleActions: actionStore.lifecycle,
            detailOpenActions: actionStore.detailOpen
        )
    }
}

/// Both outcomes reuse the existing top notice presentation. Only success is icon-only.
enum HomeRecommendationFeedbackNotice: Equatable {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .success(let message), .failure(let message): message
        }
    }
}

struct HomeRecommendationFeedbackNoticeView: View {
    let notice: HomeRecommendationFeedbackNotice

    var body: some View {
        Group {
            switch notice {
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(notice.message)
            case .failure(let message):
                VideoDetailNoticeLabel(message: message, systemImage: "info.circle")
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .allowsHitTesting(false)
    }
}

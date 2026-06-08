import SwiftUI
import UIKit

private extension Color {
    static let videoDetailSecondarySurface = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : .secondarySystemGroupedBackground
    })
}

struct VideoDetailRelatedSection: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var store: VideoDetailRelatedRenderStore
    let layoutWidth: CGFloat
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let retryRelated: () async -> Void
    @State private var preloadedRelatedVideos = Set<String>()

    var body: some View {
        let relatedItems = store.relatedItems
        let layout = VideoDetailRelatedListLayout(layoutWidth: layoutWidth)

        VStack(alignment: .leading, spacing: 9) {
            VideoDetailRelatedHeader(isLoading: store.state.isLoading)
                .padding(.horizontal, layout.horizontalPadding)

            if !relatedItems.isEmpty {
                VideoDetailRelatedList(
                    items: relatedItems,
                    layout: layout,
                    beginPreload: beginRelatedPreloadIfNeeded
                )
                .padding(.horizontal, layout.horizontalPadding)
                .transition(.opacity)
            } else {
                relatedPlaceholderContent(layout: layout)
            }
        }
        .frame(width: layoutWidth, alignment: .leading)
        .padding(.top, 1)
        .padding(.bottom, 7)
    }

    private func beginRelatedPreloadIfNeeded(_ video: VideoItem) {
        guard !video.bvid.isEmpty,
              !preloadedRelatedVideos.contains(video.bvid),
              preloadedRelatedVideos.count < 1,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }
        let api = dependencies.api
        let preferredQuality = runtimeSettings.preferredVideoQuality
        let cdnPreference = runtimeSettings.effectivePlaybackCDNPreference
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: runtimeSettings.playbackAutoOptimizationEnabled
        )
        guard playbackAdaptationProfile.backgroundPreloadLimit > 1 else { return }
        preloadedRelatedVideos.insert(video.bvid)
        Task(priority: .background) {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                priority: .background,
                warmsMedia: false,
                mediaWarmupDelay: 0,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    @ViewBuilder
    private func relatedPlaceholderContent(layout: VideoDetailRelatedListLayout) -> some View {
        if case .failed(let message) = store.state {
            RelatedVideoRetryState(
                message: store.lastLoadTimedOut ? "相关推荐加载超时，可以稍后重试。" : message
            ) {
                Task {
                    await retryRelated()
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, 16)
        } else {
            VideoDetailRelatedPlaceholderList(
                layout: layout,
                isLoading: store.state.isLoading
            )
            .padding(.horizontal, layout.horizontalPadding)
            .allowsHitTesting(false)
        }
    }
}

struct InitialRelatedSection: View {
    let layoutWidth: CGFloat

    var body: some View {
        let layout = VideoDetailRelatedListLayout(layoutWidth: layoutWidth)

        VStack(alignment: .leading, spacing: 9) {
            VideoDetailRelatedHeader(isLoading: false)
                .padding(.horizontal, layout.horizontalPadding)

            VideoDetailRelatedPlaceholderList(layout: layout, isLoading: true)
                .padding(.horizontal, layout.horizontalPadding)
        }
        .frame(width: layoutWidth, alignment: .leading)
        .padding(.top, 1)
        .padding(.bottom, 7)
        .allowsHitTesting(false)
    }
}

struct NativeLoadingIndicator: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
    }
}

private struct VideoDetailRelatedListLayout {
    let layoutWidth: CGFloat
    let horizontalPadding: CGFloat = 12

    var contentWidth: CGFloat {
        max(layoutWidth - horizontalPadding * 2, 1)
    }

    var coverWidth: CGFloat {
        min(max(contentWidth * 0.40, 132), 160)
    }

    var coverSize: CGSize {
        CGSize(width: coverWidth, height: coverWidth * 9 / 16)
    }

    var dividerLeadingPadding: CGFloat {
        coverWidth + 10
    }
}

private struct VideoDetailRelatedHeader: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("相关推荐")
                .font(.headline)

            Spacer()

            if isLoading {
                NativeLoadingIndicator()
                    .controlSize(.small)
                    .tint(.secondary)
            }
        }
    }
}

private struct VideoDetailRelatedList: View {
    let items: [VideoDetailRelatedDisplayItem]
    let layout: VideoDetailRelatedListLayout
    let beginPreload: (VideoItem) -> Void

    var body: some View {
        let lastRelatedVideoID = items.last?.id

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 0) {
                    VideoRouteLink(item.video) {
                        VideoDetailRelatedRow(
                            item: item,
                            coverSize: layout.coverSize
                        )
                        .equatable()
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        beginPreload(item.video)
                    }

                    if item.id != lastRelatedVideoID {
                        Divider()
                            .padding(.leading, layout.dividerLeadingPadding)
                    }
                }
            }
        }
    }
}

private struct VideoDetailRelatedRow: View, Equatable {
    let item: VideoDetailRelatedDisplayItem
    let coverSize: CGSize

    static func == (lhs: VideoDetailRelatedRow, rhs: VideoDetailRelatedRow) -> Bool {
        lhs.item == rhs.item && lhs.coverSize == rhs.coverSize
    }

    var body: some View {
        VideoCompactListRow(
            display: item.display,
            coverSize: coverSize,
            coverMaximumPixelLength: PlaybackEnvironment.current.shouldPreferConservativePlayback ? 360 : 480,
            coverCornerRadius: 10,
            titleMinHeight: 36,
            authorStyle: .plain,
            metadataStyle: .related
        )
        .padding(.vertical, 9)
    }
}

private struct VideoDetailRelatedPlaceholderList: View {
    let layout: VideoDetailRelatedListLayout
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                VideoCompactListPlaceholderRow(
                    coverSize: layout.coverSize,
                    fill: Color.videoDetailSecondarySurface,
                    isLoading: isLoading
                )
                .padding(.vertical, 9)

                Divider()
                    .padding(.leading, layout.dividerLeadingPadding)
            }
        }
    }
}

private struct RelatedVideoRetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label("相关推荐加载失败", systemImage: "rectangle.stack.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Button {
                retry()
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

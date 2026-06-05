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
        let lastRelatedVideoID = relatedItems.last?.id
        let horizontalPadding: CGFloat = 12
        let contentWidth = max(layoutWidth - horizontalPadding * 2, 1)
        let coverWidth = min(max(contentWidth * 0.40, 132), 160)

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("相关推荐")
                    .font(.headline)

                Spacer()

                if store.state.isLoading {
                    NativeLoadingIndicator()
                        .controlSize(.small)
                        .tint(.secondary)
                }
            }
            .padding(.horizontal, horizontalPadding)

            if !relatedItems.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(relatedItems) { item in
                        VStack(spacing: 0) {
                            VideoRouteLink(item.video) {
                                RelatedVideoListRow(
                                    item: item,
                                    coverWidth: coverWidth
                                )
                                .equatable()
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                beginRelatedPreloadIfNeeded(item.video)
                            }

                            if item.id != lastRelatedVideoID {
                                Divider()
                                    .padding(.leading, coverWidth + 10)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .transition(.opacity)
            } else {
                relatedPlaceholderContent(coverWidth: coverWidth, horizontalPadding: horizontalPadding)
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
                warmsMedia: true,
                mediaWarmupDelay: 0.25,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    @ViewBuilder
    private func relatedPlaceholderContent(coverWidth: CGFloat, horizontalPadding: CGFloat) -> some View {
        if case .failed(let message) = store.state {
            RelatedVideoRetryState(
                message: store.lastLoadTimedOut ? "相关推荐加载超时，可以稍后重试。" : message
            ) {
                Task {
                    await retryRelated()
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    RelatedVideoListPlaceholderRow(
                        coverWidth: coverWidth,
                        isLoading: store.state.isLoading
                    )

                    Divider()
                        .padding(.leading, coverWidth + 10)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .allowsHitTesting(false)
        }
    }
}

struct InitialRelatedSection: View {
    let layoutWidth: CGFloat

    var body: some View {
        let horizontalPadding: CGFloat = 12
        let contentWidth = max(layoutWidth - horizontalPadding * 2, 1)
        let coverWidth = min(max(contentWidth * 0.40, 132), 160)

        VStack(alignment: .leading, spacing: 9) {
            Text("相关推荐")
                .font(.headline)
                .padding(.horizontal, horizontalPadding)

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    RelatedVideoListPlaceholderRow(
                        coverWidth: coverWidth,
                        isLoading: true
                    )

                    Divider()
                        .padding(.leading, coverWidth + 10)
                }
            }
            .padding(.horizontal, horizontalPadding)
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

private struct RelatedVideoListRow: View, Equatable {
    let item: VideoDetailRelatedDisplayItem
    let coverWidth: CGFloat
    @Environment(\.displayScale) private var displayScale

    static func == (lhs: RelatedVideoListRow, rhs: RelatedVideoListRow) -> Bool {
        lhs.item == rhs.item && lhs.coverWidth == rhs.coverWidth
    }

    private var display: VideoCardDisplayModel {
        item.display
    }

    private var coverHeight: CGFloat {
        coverWidth * 9 / 16
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 5) {
                StableVideoTitleText(display.title, style: .related, lineLimit: 2)
                    .frame(minHeight: 36, alignment: .topLeading)

                Text(display.authorName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !display.viewText.isEmpty {
                        Label(display.viewText, systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                    }

                    if !display.publishTimeText.isEmpty {
                        Text(display.viewText.isEmpty ? display.publishTimeText : "· \(display.publishTimeText)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: coverHeight, alignment: .topLeading)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.title)
    }

    private var cover: some View {
        ZStack(alignment: .bottomTrailing) {
            let size = CGSize(width: coverWidth, height: coverHeight)
            let maximumPixelLength = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 360 : 480
            CachedRemoteImage(
                url: display.coverThumbnailURL(
                    fitting: size,
                    scale: displayScale,
                    maximumPixelLength: maximumPixelLength
                ),
                fallbackURL: display.sourceCoverURL,
                targetPixelSize: display.coverTargetPixelSize(
                    fitting: size,
                    scale: displayScale,
                    maximumPixelLength: maximumPixelLength
                )
            ) { image in
                image.resizable().scaledToFill()
            } phasePlaceholder: { phase, _ in
                BiliMediaPlaceholder(
                    style: .video,
                    phase: phase,
                    showsSpinner: phase == .loading,
                    iconSize: 14
                )
            }

            if !display.durationText.isEmpty {
                VideoCoverDurationBadge(display.durationText)
                    .padding(6)
            }
        }
        .frame(width: coverWidth, height: coverHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .mediaShadow(.subtle)
    }
}

private struct RelatedVideoListPlaceholderRow: View {
    let coverWidth: CGFloat
    let isLoading: Bool

    private var coverHeight: CGFloat {
        coverWidth * 9 / 16
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.videoDetailSecondarySurface)
                .frame(width: coverWidth, height: coverHeight)

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .frame(height: 15)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .frame(width: 156, height: 15)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .frame(width: 118, height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .frame(width: 92, height: 11)
            }
            .frame(maxWidth: .infinity, minHeight: coverHeight, alignment: .topLeading)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .redacted(reason: .placeholder)
        .overlay(alignment: .center) {
            if isLoading {
                NativeLoadingIndicator()
                    .controlSize(.regular)
                    .tint(.secondary)
                    .padding(10)
                    .accessibilityLabel("正在加载相关推荐")
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

import Foundation
import SwiftUI

struct BiliPlayerViewContent: View {
    let context: BiliPlayerViewRenderContext
    let renderState: BiliPlayerViewRenderState
    @State private var isMoreControlsPresented = false
    @State private var showsRateChoices = false

    var body: some View {
        BiliPlayerSurfaceChrome(
            playbackSurface: AnyView(surfaceGestureLayer),
            state: surfaceChromeState,
            playbackControls: AnyView(playbackControls)
        )
        .sheet(isPresented: $isMoreControlsPresented) {
            BiliPlayerMoreControlsSheet(
                viewModel: context.viewModel,
                configuration: context.configuration,
                showsRateChoices: $showsRateChoices
            )
        }
    }

    private var surfaceGestureLayer: some View {
        BiliPlayerSurfaceGestureLayerHost(
            content: playbackSurface,
            visibilityActions: renderState.visibilityActions,
            speedBoostActions: renderState.speedBoostActions,
            viewModel: context.viewModel
        )
    }

    private var playbackSurface: some View {
        VideoSurfaceView(
            viewModel: context.viewModel,
            prefersNativePlaybackControls: false,
            isPictureInPictureEnabled: context.isPictureInPictureEnabled,
            disablesImplicitLayoutAnimations: context.configuration.isLayoutTransitioning,
            usesLiveSurfaceDuringLayoutTransition: context.configuration.usesLiveSurfaceDuringLayoutTransition
        )
    }

    private var playbackControls: some View {
        BiliPlayerNativeControlsHost(
            context: context,
            renderState: renderState
        )
    }

    private var surfaceChromeState: BiliPlayerSurfaceChromeState {
        BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: context.configuration.surfaceOverlay,
            rotationSnapshot: context.rotationTransitionSnapshotModel.snapshot,
            seekSnapshot: context.seekTransitionSnapshotModel.snapshot,
            rotationFallbackCoverURL: context.rotationFallbackCoverURL,
            rotationSnapshotOpacity: context.rotationTransitionSnapshotModel.opacity,
            seekSnapshotOpacity: context.seekTransitionSnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: context.configuration.isFullscreenActive
                || context.configuration.isLayoutTransitioning,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome,
            isBuffering: context.surfaceState.isBuffering,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            isSpeedBoostActive: context.speedBoostModel.isActive,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topTrailingControlsAccessory: AnyView(moreControlsButton),
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            errorMessage: context.surfaceState.errorMessage
        )
    }

    private var moreControlsButton: some View {
        BiliPlayerMoreControlsButton(
            open: {
                showsRateChoices = false
                isMoreControlsPresented = true
            }
        )
    }
}

private struct BiliPlayerMoreControlsButton: View {
    @Environment(\.playerNativeControlMetrics) private var metrics
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "ellipsis")
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .frame(width: metrics.controlHeight, height: metrics.controlHeight)
        }
        .biliPlayerCompactGlassCircle(metrics: metrics)
        .accessibilityLabel("更多播放设置")
    }
}

private struct BiliPlayerMoreControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PlayerStateViewModel
    let configuration: BiliPlayerViewConfiguration
    @Binding var showsRateChoices: Bool

    var body: some View {
        NavigationStack {
            List {
                if showsRateChoices {
                    ForEach(BiliPlaybackRate.allCases) { rate in
                        Button {
                            viewModel.setPlaybackRate(rate)
                            dismiss()
                        } label: {
                            Label(
                                rate.title,
                                systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer"
                            )
                        }
                    }
                } else {
                    if configuration.onShowDanmakuSettings != nil || configuration.onToggleDanmaku != nil {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showDanmakuSettings()
                            }
                        } label: {
                            Label("弹幕设置", systemImage: "text.bubble")
                        }
                    }

                    Button {
                        showsRateChoices = true
                    } label: {
                        HStack {
                            Label("倍速", systemImage: "speedometer")
                            Spacer()
                            Text(viewModel.playbackRate.title)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Label("解码格式：\(decodeTitle)", systemImage: "cpu")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .navigationTitle(showsRateChoices ? "倍速" : "播放设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func showDanmakuSettings() {
        if let onShowDanmakuSettings = configuration.onShowDanmakuSettings {
            onShowDanmakuSettings()
        } else {
            configuration.onToggleDanmaku?()
        }
    }

    private var decodeTitle: String {
        let description = viewModel.engineDiagnostics.compactDescription
        return description.isEmpty ? "未知" : description
    }
}

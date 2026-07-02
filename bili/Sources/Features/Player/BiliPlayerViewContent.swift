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
            disablesImplicitLayoutAnimations: context.configuration.isLayoutTransitioning
                || context.configuration.disablesSurfaceImplicitLayoutAnimations,
            usesLiveSurfaceDuringLayoutTransition: context.configuration.usesLiveSurfaceDuringLayoutTransition,
            isLayoutTransitioningForSurfaceHandoff: context.configuration.isLayoutTransitioning
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
            playbackControlsOpacity: context.playbackControlsVisibility.opacity,
            playbackControlsAllowsHitTesting: context.playbackControlsVisibility.acceptsHitTesting,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topTrailingControlsAccessory: AnyView(moreControlsButton),
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            contentInsets: EdgeInsets(),
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
                .foregroundStyle(.white)
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

                    Label("视频格式：\(videoFormatTitle)", systemImage: "film")
                        .foregroundStyle(.secondary)

                    Label("解码：\(decodeTitle)", systemImage: "cpu")
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
        let diagnostics = viewModel.engineDiagnostics
        var parts = [diagnostics.decodePath.title]
        if diagnostics.hardwareDecodeRequested {
            parts.append("硬解")
        }
        if let isHardwareDecodeCompatible = diagnostics.isHardwareDecodeCompatible {
            parts.append(isHardwareDecodeCompatible ? "硬解兼容" : "硬解不兼容")
        }
        return parts.joined(separator: " · ")
    }

    private var videoFormatTitle: String {
        let diagnostics = viewModel.engineDiagnostics
        var parts = [String]()
        if let codec = diagnostics.codec, !codec.isEmpty {
            parts.append(codecDisplayName(codec))
        }
        if let resolution = diagnostics.resolution, !resolution.isEmpty {
            parts.append(resolution)
        }
        if let frameRate = diagnostics.frameRate, !frameRate.isEmpty {
            parts.append(frameRate)
        }
        if let dynamicRangeTitle {
            parts.append(dynamicRangeTitle)
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        let description = viewModel.engineDiagnostics.compactDescription
        return description.isEmpty ? "未知" : description
    }

    private var dynamicRangeTitle: String? {
        switch viewModel.engineDiagnostics.dynamicRange {
        case .sdr:
            return nil
        case .hdr10:
            return "HDR"
        case .hlg:
            return "HLG"
        case .dolbyVision:
            return "杜比视界"
        }
    }

    private func codecDisplayName(_ codec: String) -> String {
        switch codec.uppercased() {
        case "AVC":
            return "H.264 / AVC"
        case "HEVC":
            return "HEVC / H.265"
        default:
            return codec
        }
    }
}

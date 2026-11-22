import SwiftUI

struct CommentSheetToolbarConfiguration {
    let onDismiss: () -> Void
    let onRefresh: () -> Void
}

private struct CommentSheetToolbarConfigurationKey: EnvironmentKey {
    static let defaultValue = CommentSheetToolbarConfiguration(onDismiss: {}, onRefresh: {})
}

// Preserve the app's resolved content appearance across presentation boundaries.
// Unlike colorScheme, this value is not replaced by a UIKit sheet/host trait.
private struct AppContentColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

extension EnvironmentValues {
    var appContentColorScheme: ColorScheme? {
        get { self[AppContentColorSchemeKey.self] }
        set { self[AppContentColorSchemeKey.self] = newValue }
    }

    var commentSheetToolbarConfiguration: CommentSheetToolbarConfiguration {
        get { self[CommentSheetToolbarConfigurationKey.self] }
        set { self[CommentSheetToolbarConfigurationKey.self] = newValue }
    }

    /// Maximum detent height for sheets presented on the video detail page in stacked
    /// (portrait) layout so sheets stay strictly below the video player instead of
    /// using a hardcoded 70% height limit. `nil` outside stacked video detail (e.g. Dynamic page).
    @Entry var videoDetailBelowPlayerSheetMaxHeight: CGFloat? = nil
}

enum VideoDetailSheetHeightPolicy {
    /// Computes a SwiftUI `.presentationDetents([.height(...)])` value whose top edge stays
    /// strictly below `playerBottomY` in stacked video detail layout (never covering the video).
    static func belowVideoDetentHeight(
        containerHeight: CGFloat,
        playerBottomY: CGFloat,
        bottomSafeAreaInset: CGFloat
    ) -> CGFloat? {
        guard containerHeight.isFinite, playerBottomY.isFinite, containerHeight > 0 else {
            return nil
        }
        let belowVideo = containerHeight - max(playerBottomY, 0)
        guard belowVideo > 0 else { return nil }
        // On iOS 26/27, `.presentationDetents([.height(h)])` positions the floating Liquid Glass
        // sheet's top edge above the bottom safe area (~`h + bottomSafeArea - 11pt`). Subtracting
        // `max(bottomSafeAreaInset, 12)` guarantees the sheet top edge stays strictly below
        // `playerBottomY` across 21:9, 16:9, 4:3, 1:1, and 9:16 videos.
        let clearance = max(bottomSafeAreaInset, 12)
        let adjusted = (belowVideo - clearance).rounded(.down)
        if adjusted >= 160 {
            return adjusted
        }
        return max(min(belowVideo.rounded(.down), 160), 120)
    }
}

enum CommentSheetPresentationPolicy {
    static func shouldLimitHeight(
        limitsMaxHeight: Bool,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        limitsMaxHeight && verticalSizeClass != .compact
    }

    static func detents(
        limitsMaxHeight: Bool,
        verticalSizeClass: UserInterfaceSizeClass?,
        videoDetailMaxHeight: CGFloat? = nil
    ) -> Set<PresentationDetent> {
        if shouldLimitHeight(limitsMaxHeight: limitsMaxHeight, verticalSizeClass: verticalSizeClass) {
            if let videoDetailMaxHeight, videoDetailMaxHeight > 0 {
                return [.height(videoDetailMaxHeight)]
            }
            return [.fraction(CommentInteractionSettings.limitedSheetDetentFraction)]
        }
        return [.medium, .large]
    }
}

private struct CommentSheetPresentation: ViewModifier {
    @Environment(\.colorScheme) private var inheritedColorScheme
    @Environment(\.appContentColorScheme) private var appContentColorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.videoDetailSplitSheetDismiss) private var splitSheetDismiss
    @Environment(\.videoDetailSplitColumnOverlay) private var splitColumnOverlay
    @Environment(\.videoDetailBelowPlayerSheetMaxHeight) private var videoDetailBelowPlayerSheetMaxHeight
    @AppStorage(CommentInteractionSettings.limitsSheetMaxHeightKey)
    private var limitsSheetMaxHeight = CommentInteractionSettings.defaultLimitsSheetMaxHeight
    @State private var selectedDetent: PresentationDetent = .medium
    let onDismiss: () -> Void
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        let contentColorScheme = appContentColorScheme ?? inheritedColorScheme
        let resolvedVideoDetailMaxHeight = videoDetailBelowPlayerSheetMaxHeight
            ?? splitColumnOverlay?.stackedBelowPlayerSheetMaxHeight
        let shouldLimitHeight = (resolvedVideoDetailMaxHeight != nil || horizontalSizeClass != .regular)
            && CommentSheetPresentationPolicy.shouldLimitHeight(
                limitsMaxHeight: limitsSheetMaxHeight,
                verticalSizeClass: verticalSizeClass
            )
        if splitSheetDismiss != nil {
            content
                .environment(\.colorScheme, contentColorScheme)
                .environment(
                    \.commentSheetToolbarConfiguration,
                    CommentSheetToolbarConfiguration(onDismiss: onDismiss, onRefresh: onRefresh)
                )
        } else {
            content
                .environment(\.colorScheme, contentColorScheme)
                // The video host can request dark status-bar contrast while its
                // content stays light. Keep this presentation's UIKit background
                // and its SwiftUI comment text on the same appearance.
                .preferredColorScheme(contentColorScheme)
                .commentSheetHeightDetents(
                    limitsHeight: shouldLimitHeight,
                    videoDetailMaxHeight: resolvedVideoDetailMaxHeight,
                    selectedDetent: $selectedDetent
                )
                .presentationDragIndicator(.visible)
                .environment(
                    \.commentSheetToolbarConfiguration,
                    CommentSheetToolbarConfiguration(onDismiss: onDismiss, onRefresh: onRefresh)
                )
        }
    }
}

private extension View {
    @ViewBuilder
    func commentSheetHeightDetents(
        limitsHeight: Bool,
        videoDetailMaxHeight: CGFloat?,
        selectedDetent: Binding<PresentationDetent>
    ) -> some View {
        if limitsHeight {
            if let videoDetailMaxHeight, videoDetailMaxHeight > 0 {
                self
                    .presentationDetents([.height(videoDetailMaxHeight)])
                    .presentationContentInteraction(.scrolls)
            } else {
                self
                    .presentationDetents([.fraction(CommentInteractionSettings.limitedSheetDetentFraction)])
                    .presentationContentInteraction(.scrolls)
            }
        } else {
            self
                .presentationDetents([.medium, .large], selection: selectedDetent)
                .presentationContentInteraction(.resizes)
        }
    }
}

private struct VideoDetailBelowPlayerSheetDetentsModifier: ViewModifier {
    @Environment(\.videoDetailBelowPlayerSheetMaxHeight) private var belowPlayerMaxHeight
    @Environment(\.videoDetailSplitColumnOverlay) private var splitColumnOverlay
    let fallback: Set<PresentationDetent>

    func body(content: Content) -> some View {
        if let maxHeight = belowPlayerMaxHeight ?? splitColumnOverlay?.stackedBelowPlayerSheetMaxHeight,
           maxHeight > 0 {
            content
                .presentationDetents([.height(maxHeight)])
                .presentationContentInteraction(.scrolls)
        } else {
            content.presentationDetents(fallback)
        }
    }
}

extension View {
    func commentSheetPresentation(
        onDismiss: @escaping () -> Void = {},
        onRefresh: @escaping () -> Void = {}
    ) -> some View {
        modifier(CommentSheetPresentation(onDismiss: onDismiss, onRefresh: onRefresh))
    }

    func videoDetailBelowPlayerSheetDetents(
        fallback: Set<PresentationDetent> = [.medium, .large]
    ) -> some View {
        modifier(VideoDetailBelowPlayerSheetDetentsModifier(fallback: fallback))
    }
}

import CoreGraphics
import SwiftUI
import UIKit

/// Unified width tier resolved from container geometry and SwiftUI size classes
/// rather than device model names.
nonisolated enum AdaptiveWidthTier: Int, Comparable, Sendable {
    case compact = 0
    case medium = 1
    case expanded = 2
    case wide = 3

    static func < (lhs: AdaptiveWidthTier, rhs: AdaptiveWidthTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Adaptive presentation mode for the video detail page.
nonisolated enum VideoDetailAdaptiveMode: Equatable, Sendable {
    case compactStacked
    case twoColumnSplit
    case fullscreen
}

/// Shared, pure-geometry layout policy for iPhone, iPhone Duo (cover/unfolded),
/// iPad (full screen, Split View, Stage Manager), and external displays.
nonisolated enum AdaptiveLayoutPolicy {
    static let compactHorizontalInset: CGFloat = 20
    static let mediumHorizontalInset: CGFloat = 24
    static let expandedHorizontalInset: CGFloat = 28
    static let wideHorizontalInset: CGFloat = 32

    static let readingColumnMaxWidth: CGFloat = 720
    static let formListMaxWidth: CGFloat = 680
    static let readableListMaxWidth: CGFloat = 760
    static let singleColumnFeedMaxWidth: CGFloat = 640
    static let multiColumnFeedMaxWidth: CGFloat = 1360
    static let searchResultsMaxWidth: CGFloat = 1280

    static let videoDetailSplitMinWidth: CGFloat = 700
    static let videoDetailSplitMinHeight: CGFloat = 460

    static func widthTier(
        containerSize: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        adaptiveEnabled: Bool = true
    ) -> AdaptiveWidthTier {
        guard adaptiveEnabled else { return .compact }
        let width = max(containerSize.width, 0)
        let height = max(containerSize.height, 0)
        guard width > 0 else { return .compact }

        // Keep short compact-width phone landscape (e.g. 956x440 iPhone landscape)
        // in compact tier when height is clearly phone-landscape constrained and
        // horizontalSizeClass is compact.
        if horizontalSizeClass == .compact, height > 0, height < 500 {
            return .compact
        }

        switch width {
        case ..<560:
            return .compact
        case 560..<840:
            return .medium
        case 840..<1120:
            return .expanded
        default:
            return .wide
        }
    }

    static func horizontalInset(
        for containerWidth: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        containerHeight: CGFloat = 900,
        adaptiveEnabled: Bool = true
    ) -> CGFloat {
        switch widthTier(
            containerSize: CGSize(width: containerWidth, height: containerHeight),
            horizontalSizeClass: horizontalSizeClass,
            adaptiveEnabled: adaptiveEnabled
        ) {
        case .compact:
            return compactHorizontalInset
        case .medium:
            return mediumHorizontalInset
        case .expanded:
            return expandedHorizontalInset
        case .wide:
            return wideHorizontalInset
        }
    }

    /// Adaptive column count for card grids (Home double-column, Live rooms, Uploader videos).
    static func feedGridColumnCount(
        containerWidth: CGFloat,
        containerHeight: CGFloat = 900,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        horizontalInset: CGFloat,
        columnSpacing: CGFloat,
        preferredMinimumCardWidth: CGFloat = 205,
        maxColumns: Int = 5,
        adaptiveEnabled: Bool = true
    ) -> Int {
        let tier = widthTier(
            containerSize: CGSize(width: containerWidth, height: containerHeight),
            horizontalSizeClass: horizontalSizeClass,
            adaptiveEnabled: adaptiveEnabled
        )
        guard tier != .compact else { return 2 }

        let effectiveWidth = min(max(containerWidth, 0), multiColumnFeedMaxWidth)
        let availableWidth = max(effectiveWidth - horizontalInset * 2, 0)
        let minCardWidth = tier >= .expanded ? max(preferredMinimumCardWidth, 215) : preferredMinimumCardWidth
        let rawColumns = Int(floor((availableWidth + columnSpacing) / (minCardWidth + columnSpacing)))
        return max(2, min(maxColumns, rawColumns))
    }

    /// Adaptive column count for bordered compact horizontal rows (Search results, bordered single-column).
    static func listCardColumnCount(
        containerWidth: CGFloat,
        containerHeight: CGFloat = 900,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        adaptiveEnabled: Bool = true
    ) -> Int {
        let tier = widthTier(
            containerSize: CGSize(width: containerWidth, height: containerHeight),
            horizontalSizeClass: horizontalSizeClass,
            adaptiveEnabled: adaptiveEnabled
        )
        switch tier {
        case .compact:
            return 1
        case .medium:
            return containerWidth >= 680 ? 2 : 1
        case .expanded:
            return 2
        case .wide:
            return 3
        }
    }

    static func searchDiscoveryColumnCount(
        containerWidth: CGFloat,
        containerHeight: CGFloat = 900,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        adaptiveEnabled: Bool = true
    ) -> Int {
        switch widthTier(
            containerSize: CGSize(width: containerWidth, height: containerHeight),
            horizontalSizeClass: horizontalSizeClass,
            adaptiveEnabled: adaptiveEnabled
        ) {
        case .compact:
            return 2
        case .medium:
            return 3
        case .expanded, .wide:
            return 4
        }
    }

    static func centeredContentWidth(
        containerWidth: CGFloat,
        maxContentWidth: CGFloat,
        horizontalInset: CGFloat
    ) -> CGFloat {
        let bounded = min(max(containerWidth, 0), maxContentWidth)
        return max(bounded - horizontalInset * 2, 0)
    }

    /// Computes horizontal scroll content margins that keep insetGrouped lists /
    /// settings / notification pages within a comfortable readable width on large
    /// screens while preserving full-width scrolling and edge scroll indicators.
    static func readableHorizontalContentMargin(
        containerWidth: CGFloat,
        baseInset: CGFloat,
        maxContentWidth: CGFloat = formListMaxWidth,
        adaptiveEnabled: Bool = true
    ) -> CGFloat {
        let normalizedBase = max(baseInset, 0)
        guard adaptiveEnabled, containerWidth > 0, maxContentWidth > 0 else {
            return normalizedBase
        }
        let centeredMargin = floor((containerWidth - maxContentWidth) / 2)
        return max(normalizedBase, centeredMargin)
    }

    /// Adaptive column count for Xiaohongshu-style masonry waterfall feeds on all
    /// devices (2 cols on iPhone/Duo cover, 3 cols on Duo inner portrait, 4 cols
    /// on Duo inner landscape / iPad portrait, 5 cols on iPad 13" landscape+).
    static func dynamicWaterfallColumnCount(
        containerWidth: CGFloat,
        horizontalInset: CGFloat = 12,
        columnSpacing: CGFloat = 10
    ) -> Int {
        let width = max(containerWidth, 0)
        guard width > 0 else { return 2 }
        switch width {
        case ..<560:
            return 2
        case 560..<840:
            return 3
        case 840..<1180:
            return 4
        default:
            let effectiveWidth = min(width, multiColumnFeedMaxWidth)
            let available = max(effectiveWidth - horizontalInset * 2, 0)
            let raw = Int(floor((available + columnSpacing) / (230 + columnSpacing)))
            return max(4, min(5, raw))
        }
    }

    /// Determines whether the video detail page should use a side-by-side two-column layout,
    /// stacked portrait layout, or fullscreen playback.
    static func videoDetailMode(
        containerSize: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        isFullscreenActive: Bool,
        adaptiveEnabled: Bool = true
    ) -> VideoDetailAdaptiveMode {
        if isFullscreenActive {
            return .fullscreen
        }
        guard adaptiveEnabled else {
            return .compactStacked
        }
        if horizontalSizeClass == .compact, containerSize.height < 500 {
            return .compactStacked
        }
        if containerSize.width > containerSize.height,
           containerSize.width >= videoDetailSplitMinWidth,
           containerSize.height >= videoDetailSplitMinHeight {
            return .twoColumnSplit
        }
        return .compactStacked
    }

    /// Computes left (player stage) and right (info/comments) column widths for `.twoColumnSplit`.
    static func videoDetailSplitColumnWidths(totalWidth: CGFloat) -> (playerColumnWidth: CGFloat, contentColumnWidth: CGFloat) {
        let safeTotal = max(totalWidth, videoDetailSplitMinWidth)
        let preferredRight = min(max((safeTotal * 0.40).rounded(), 330), 460)
        let playerColumnWidth = max(safeTotal - preferredRight, 360)
        let contentColumnWidth = max(safeTotal - playerColumnWidth, 320)
        return (playerColumnWidth, contentColumnWidth)
    }

    /// Whether the active container/window exposes a portrait asymmetric vertical
    /// system chrome rail (iPhone Duo folded cover display in portrait, where one
    /// horizontal edge reserves ~84pt for the vertical status/toolbar/tab rail while
    /// the opposite horizontal edge stays minimal). Large-screen landscape (Duo inner
    /// landscape / iPad landscape) uses `.twoColumnSplit` with its own right-column
    /// phone-style bottom toolbar instead.
    static func usesVerticalTrailingChromeRail(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> Bool {
        guard containerSize.width > 0, containerSize.height > 0 else { return false }
        let maxHorizontalInset = max(safeAreaInsets.leading, safeAreaInsets.trailing)
        let minHorizontalInset = min(safeAreaInsets.leading, safeAreaInsets.trailing)
        return containerSize.height > containerSize.width
            && maxHorizontalInset >= 50
            && minHorizontalInset <= 16
    }

    @MainActor
    static func usesVerticalTrailingChromeRail(for window: UIWindow?) -> Bool {
        guard let window else { return false }
        let insets = window.safeAreaInsets
        return usesVerticalTrailingChromeRail(
            containerSize: window.bounds.size,
            safeAreaInsets: EdgeInsets(
                top: insets.top,
                leading: insets.left,
                bottom: insets.bottom,
                trailing: insets.right
            )
        )
    }

    /// Returns the horizontal content bounds (left `height:width = 16:9` strip)
    /// for an iPhone Duo folded cover display when a vertical system chrome rail
    /// occupies the trailing edge (e.g. `466×678pt` with ~84pt trailing rail).
    ///
    /// Page backgrounds continue to span the full container width underneath the
    /// right-side controls, while foreground display elements remain inside this
    /// left 9:16 portrait region and never intersect the trailing chrome rail.
    /// Returns `nil` when not in folded Duo vertical-rail mode.
    static func duoFoldedContentHorizontalBounds(
        containerBounds: CGRect,
        safeAreaInsets: EdgeInsets
    ) -> (minX: CGFloat, width: CGFloat)? {
        guard usesVerticalTrailingChromeRail(
            containerSize: containerBounds.size,
            safeAreaInsets: safeAreaInsets
        ) else {
            return nil
        }
        let safeLeading = max(safeAreaInsets.leading, 0)
        let safeTrailing = max(safeAreaInsets.trailing, 0)
        let safeWidth = max(containerBounds.width - safeLeading - safeTrailing, 0)
        let portrait16By9Width = (containerBounds.height * 9 / 16).rounded(.down)
        let contentWidth = min(safeWidth, portrait16By9Width)
        guard contentWidth > 0 else { return nil }
        return (minX: containerBounds.minX + safeLeading, width: contentWidth)
    }

    /// Whether the active container/window is the unfolded inner display of an
    /// iPhone Duo (phone idiom with short side >= 540pt, covering both portrait
    /// `669×951pt` and landscape `951×669pt`). Excludes the folded Duo cover
    /// display (`466×678pt`), all standard iPhones (short side <= 440pt), and
    /// all iPads (`userInterfaceIdiom == .pad`).
    static func isDuoUnfoldedInnerDisplay(
        containerSize: CGSize,
        userInterfaceIdiom: UIUserInterfaceIdiom
    ) -> Bool {
        guard userInterfaceIdiom == .phone else { return false }
        let minSide = min(containerSize.width, containerSize.height)
        return minSide >= 540
    }

    /// Whether a scene/window should allow all orientations natively (iPad, Duo unfolded,
    /// regular-width multitasking) instead of locking root screens to portrait.
    @MainActor
    static func allowsUnrestrictedRootOrientation(
        for window: UIWindow?
    ) -> Bool {
        guard let window else {
            return UIDevice.current.userInterfaceIdiom == .pad
        }
        if window.traitCollection.userInterfaceIdiom == .pad {
            return true
        }
        let bounds = window.bounds.size
        let minSide = min(bounds.width, bounds.height)
        if window.traitCollection.verticalSizeClass == .compact {
            return false
        }
        if minSide > 0, minSide < 540 {
            return false
        }
        if window.traitCollection.horizontalSizeClass == .regular {
            return true
        }
        return minSide >= 540
    }

    /// Whether window resize/rotation in this window should keep embedded video detail
    /// in adaptive split/stacked mode rather than auto-entering fullscreen-only playback.
    @MainActor
    static func treatsLandscapeRotationAsSplitDetail(
        containerSize: CGSize,
        traitCollection: UITraitCollection?,
        adaptiveEnabled: Bool
    ) -> Bool {
        guard adaptiveEnabled else { return false }
        if containerSize.height > 0, containerSize.height < videoDetailSplitMinHeight {
            return false
        }
        if traitCollection?.userInterfaceIdiom == .pad {
            return true
        }
        if traitCollection?.verticalSizeClass == .compact {
            return false
        }
        if min(containerSize.width, containerSize.height) >= 540 {
            return true
        }
        return traitCollection?.horizontalSizeClass == .regular && traitCollection?.verticalSizeClass == .regular
    }
}

/// Optional SwiftUI modifier to constrain reading-heavy columns (Dynamic feed, Article reader)
/// while keeping full-width edge-to-edge scrolling and pull-to-refresh intact.
struct AdaptiveReadableWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var libraryStore: LibraryStore
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if libraryStore.adaptiveLargeScreenLayoutExperimentEnabled {
            content
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    @Entry var isDuoUnfoldedInnerDisplay = false
}

extension View {
    func adaptiveReadableWidth(maxWidth: CGFloat = AdaptiveLayoutPolicy.readingColumnMaxWidth) -> some View {
        modifier(AdaptiveReadableWidthModifier(maxWidth: maxWidth))
    }

    /// Disables the iOS 27.1 vertical system bar and hides status bar / persistent
    /// system overlays when full-bleed fullscreen is requested (e.g. whenever
    /// iPhone Duo's unfolded inner display is active or during immersive video).
    @ViewBuilder
    func adaptiveDuoFullscreenChrome(isHidden: Bool) -> some View {
        if #available(iOS 27.1, *) {
            self
                .toolbarVerticalBehavior(isHidden ? .disabled : .automatic)
                .statusBarHidden(isHidden)
                .persistentSystemOverlays(isHidden ? .hidden : .visible)
        } else {
            self
                .statusBarHidden(isHidden)
                .persistentSystemOverlays(isHidden ? .hidden : .visible)
        }
    }

    /// Respects iPhone Duo / iOS 27.1 hardware occlusion and hinge division reserved regions
    /// when running on iOS 27.1+, while remaining a clean no-op on iOS 26.1–27.0.
    @ViewBuilder
    func adaptiveReservedRegionPadding(edges: Edge.Set = [.horizontal]) -> some View {
        if #available(iOS 27.1, *) {
            modifier(AdaptiveReservedRegionPaddingModifier(edges: edges))
        } else {
            self
        }
    }
}

@available(iOS 27.1, *)
private struct AdaptiveReservedRegionPaddingModifier: ViewModifier {
    let edges: Edge.Set
    @State private var leadingOcclusionInset: CGFloat = 0
    @State private var trailingOcclusionInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.leading, edges.contains(.leading) ? leadingOcclusionInset : 0)
            .padding(.trailing, edges.contains(.trailing) ? trailingOcclusionInset : 0)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateInsets(proxy: proxy) }
                        .onChange(of: proxy.size) { _, _ in updateInsets(proxy: proxy) }
                }
            }
    }

    private func updateInsets(proxy: GeometryProxy) {
        let regions = proxy.reservedRegions(kind: .occlusion)
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        let width = proxy.size.width
        guard width > 0 else { return }
        for region in regions {
            guard region.isActive else { continue }
            let rect = region.frame
            guard rect.width > 0, rect.height > 0 else { continue }
            if rect.minX <= 8, rect.maxX < width * 0.4 {
                leading = max(leading, rect.maxX)
            } else if rect.maxX >= width - 8, rect.minX > width * 0.6 {
                trailing = max(trailing, width - rect.minX)
            }
        }
        if abs(leadingOcclusionInset - leading) > 0.5 {
            leadingOcclusionInset = leading
        }
        if abs(trailingOcclusionInset - trailing) > 0.5 {
            trailingOcclusionInset = trailing
        }
    }
}

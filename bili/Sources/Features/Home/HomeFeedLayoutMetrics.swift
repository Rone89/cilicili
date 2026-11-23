import SwiftUI

struct HomeFeedLayoutMetrics {
    let mode: HomeFeedLayout
    let doubleColumns: [GridItem]
    let feedColumns: [GridItem]
    let singleColumnColumns: [GridItem]
    let singleColumnGridSpacing: CGFloat
    let feedSpacing: CGFloat
    let feedHorizontalPadding: CGFloat
    let singleColumnHorizontalPadding: CGFloat
    let maxContentWidth: CGFloat?
    let singleColumnFixedCoverSize: CGSize?
    let doubleColumnFixedCoverSize: CGSize?
    let borderedSingleColumnCoverSize: CGSize?

    init(
        mode: HomeFeedLayout,
        containerWidth: CGFloat,
        viewportHeight: CGFloat = 900,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        standardHorizontalInset: CGFloat = 20
    ) {
        self.mode = mode
        let effectiveInset = AdaptiveLayoutPolicy.horizontalInset(
            for: containerWidth,
            horizontalSizeClass: horizontalSizeClass,
            containerHeight: viewportHeight,
            adaptiveEnabled: true
        )

        let doubleColumnSpacing: CGFloat = mode == .borderedDoubleColumn ? 12 : 14
        let doubleColumnCoverHeightRatio: CGFloat = mode == .borderedDoubleColumn ? 10 / 16 : 9 / 16
        let doubleColumnCount = AdaptiveLayoutPolicy.feedGridColumnCount(
            containerWidth: containerWidth,
            containerHeight: viewportHeight,
            horizontalSizeClass: horizontalSizeClass,
            horizontalInset: effectiveInset,
            columnSpacing: doubleColumnSpacing,
            adaptiveEnabled: true
        )
        doubleColumns = Array(
            repeating: GridItem(.flexible(), spacing: doubleColumnSpacing),
            count: doubleColumnCount
        )
        singleColumnHorizontalPadding = effectiveInset

        let resolvedSingleColumnsCount: Int
        switch mode {
        case .borderedSingleColumn:
            resolvedSingleColumnsCount = AdaptiveLayoutPolicy.listCardColumnCount(
                containerWidth: containerWidth,
                containerHeight: viewportHeight,
                horizontalSizeClass: horizontalSizeClass,
                adaptiveEnabled: true
            )
        case .singleColumn:
            resolvedSingleColumnsCount = containerWidth >= 920
                && AdaptiveLayoutPolicy.widthTier(
                    containerSize: CGSize(width: containerWidth, height: viewportHeight),
                    horizontalSizeClass: horizontalSizeClass,
                    adaptiveEnabled: true
                ) >= .expanded
                ? 2
                : 1
        case .doubleColumn, .borderedDoubleColumn:
            resolvedSingleColumnsCount = 1
        }

        let singleGridSpacing: CGFloat = mode == .borderedSingleColumn ? 12 : 18
        singleColumnGridSpacing = singleGridSpacing
        singleColumnColumns = Array(
            repeating: GridItem(.flexible(), spacing: singleGridSpacing),
            count: resolvedSingleColumnsCount
        )

        let tier = AdaptiveLayoutPolicy.widthTier(
            containerSize: CGSize(width: containerWidth, height: viewportHeight),
            horizontalSizeClass: horizontalSizeClass,
            adaptiveEnabled: true
        )
        if tier != .compact {
            switch mode {
            case .doubleColumn, .borderedDoubleColumn:
                maxContentWidth = AdaptiveLayoutPolicy.multiColumnFeedMaxWidth
            case .borderedSingleColumn:
                maxContentWidth = AdaptiveLayoutPolicy.searchResultsMaxWidth
            case .singleColumn:
                maxContentWidth = resolvedSingleColumnsCount > 1
                    ? 1120
                    : AdaptiveLayoutPolicy.singleColumnFeedMaxWidth
            }
        } else {
            maxContentWidth = nil
        }

        switch mode {
        case .singleColumn, .borderedSingleColumn:
            feedColumns = [
                GridItem(.flexible(minimum: 0), spacing: 0)
            ]
            feedSpacing = 0
            feedHorizontalPadding = 0
        case .doubleColumn:
            feedColumns = doubleColumns
            feedSpacing = 22
            feedHorizontalPadding = effectiveInset
        case .borderedDoubleColumn:
            feedColumns = doubleColumns
            feedSpacing = 18
            feedHorizontalPadding = effectiveInset
        }

        let effectiveContainerWidth = maxContentWidth.map { min(containerWidth, $0) } ?? containerWidth
        let singleWidth: CGFloat
        if resolvedSingleColumnsCount > 1 {
            singleWidth = (effectiveContainerWidth - singleColumnHorizontalPadding * 2 - singleGridSpacing * CGFloat(resolvedSingleColumnsCount - 1)) / CGFloat(resolvedSingleColumnsCount)
        } else {
            singleWidth = effectiveContainerWidth - singleColumnHorizontalPadding * 2
        }

        if singleWidth > 0 {
            singleColumnFixedCoverSize = CGSize(width: singleWidth, height: singleWidth * 9 / 16)
        } else {
            singleColumnFixedCoverSize = nil
        }

        let doubleWidth = (effectiveContainerWidth - (feedHorizontalPadding * 2) - doubleColumnSpacing * CGFloat(max(doubleColumnCount - 1, 0))) / CGFloat(max(doubleColumnCount, 1))
        if doubleWidth > 0 {
            doubleColumnFixedCoverSize = CGSize(width: doubleWidth, height: doubleWidth * doubleColumnCoverHeightRatio)
        } else {
            doubleColumnFixedCoverSize = nil
        }

        if singleWidth > 0 {
            borderedSingleColumnCoverSize = CGSize(width: 140, height: 88)
        } else {
            borderedSingleColumnCoverSize = nil
        }
    }
}

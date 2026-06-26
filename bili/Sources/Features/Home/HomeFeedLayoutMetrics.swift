import SwiftUI

struct HomeFeedLayoutMetrics {
    let mode: HomeFeedLayout
    let doubleColumns: [GridItem]
    let feedColumns: [GridItem]
    let feedSpacing: CGFloat
    let feedHorizontalPadding: CGFloat
    let singleColumnHorizontalPadding: CGFloat
    let singleColumnFixedCoverSize: CGSize?
    let doubleColumnFixedCoverSize: CGSize?

    init(mode: HomeFeedLayout, containerWidth: CGFloat) {
        self.mode = mode
        doubleColumns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        singleColumnHorizontalPadding = 12

        switch mode {
        case .singleColumn:
            feedColumns = [
                GridItem(.flexible(minimum: 0), spacing: 0)
            ]
            feedSpacing = 0
            feedHorizontalPadding = 0
        case .doubleColumn:
            feedColumns = doubleColumns
            feedSpacing = 22
            feedHorizontalPadding = 16
        }

        let singleWidth = containerWidth - singleColumnHorizontalPadding * 2
        if singleWidth > 0 {
            singleColumnFixedCoverSize = CGSize(width: singleWidth, height: singleWidth * 9 / 16)
        } else {
            singleColumnFixedCoverSize = nil
        }

        let doubleWidth = (containerWidth - (feedHorizontalPadding * 2) - 14) / 2
        if doubleWidth > 0 {
            doubleColumnFixedCoverSize = CGSize(width: doubleWidth, height: doubleWidth * 9 / 16)
        } else {
            doubleColumnFixedCoverSize = nil
        }
    }
}

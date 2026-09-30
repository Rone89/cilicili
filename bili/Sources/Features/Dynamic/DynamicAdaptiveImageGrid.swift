import SwiftUI

enum DynamicImageGridExperiments {
    static let adaptiveLayoutEnabledKey = "dynamic.imageGrid.adaptiveLayoutExperimentEnabled"
}

struct DynamicAdaptiveImageGrid: View {
    let imagesCount: Int
    let displayedImages: [DynamicImageDisplayItem]
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat
    let outerCornerRadius: CGFloat
    let accessibilityName: String?

    private let spacing: CGFloat = DynamicImageGridMetrics.spacing

    var body: some View {
        Group {
            switch displayedImages.count {
            case 2:
                twoImageLayout
            case 3:
                threeImageLayout
            case 4:
                fourImageLayout
            default:
                adaptiveRows
            }
        }
        .frame(width: width, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
    }

    private var canvasHeight: CGFloat {
        width / (16.0 / 9.0)
    }

    private var contentHeight: CGFloat {
        switch displayedImages.count {
        case 2, 3, 4:
            return canvasHeight
        default:
            let rows = CGFloat((displayedImages.count + 2) / 3)
            let squareSide = (width - spacing * 2) / 3
            return rows * squareSide + max(rows - 1, 0) * spacing
        }
    }

    private var resolvedCornerRadius: CGFloat {
        min(max(outerCornerRadius, 0), min(width, contentHeight) / 2)
    }

    private var twoImageLayout: some View {
        let tileWidth = (width - spacing) / 2

        return HStack(spacing: spacing) {
            tile(displayedImages[0], width: tileWidth, height: canvasHeight)
            tile(displayedImages[1], width: tileWidth, height: canvasHeight)
        }
        .frame(width: width, height: canvasHeight, alignment: .leading)
    }

    private var threeImageLayout: some View {
        let tileWidth = (width - spacing) / 2
        let tileHeight = (canvasHeight - spacing) / 2

        return HStack(spacing: spacing) {
            tile(displayedImages[0], width: tileWidth, height: canvasHeight)

            VStack(spacing: spacing) {
                tile(displayedImages[1], width: tileWidth, height: tileHeight)
                tile(displayedImages[2], width: tileWidth, height: tileHeight)
            }
        }
        .frame(width: width, height: canvasHeight, alignment: .leading)
    }

    private var fourImageLayout: some View {
        let tileWidth = (width - spacing) / 2
        let tileHeight = (canvasHeight - spacing) / 2

        return VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                tile(displayedImages[0], width: tileWidth, height: tileHeight)
                tile(displayedImages[1], width: tileWidth, height: tileHeight)
            }
            HStack(spacing: spacing) {
                tile(displayedImages[2], width: tileWidth, height: tileHeight)
                tile(displayedImages[3], width: tileWidth, height: tileHeight)
            }
        }
        .frame(width: width, height: canvasHeight, alignment: .topLeading)
    }

    private var adaptiveRows: some View {
        let rowCount = (displayedImages.count + 2) / 3

        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { rowIndex in
                adaptiveRow(at: rowIndex)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func adaptiveRow(at rowIndex: Int) -> some View {
        let startIndex = rowIndex * 3
        let endIndex = min(startIndex + 3, displayedImages.count)
        let items = Array(displayedImages[startIndex..<endIndex])
        let squareSide = (width - spacing * 2) / 3
        let tileWidth = (width - spacing * CGFloat(items.count - 1)) / CGFloat(items.count)

        return HStack(spacing: spacing) {
            ForEach(items) { item in
                tile(item, width: tileWidth, height: squareSide)
            }

        }
        .frame(width: width, alignment: .leading)
    }

    private func tile(
        _ item: DynamicImageDisplayItem,
        width tileWidth: CGFloat,
        height tileHeight: CGFloat
    ) -> some View {
        let tile = DynamicImageGridTile(
            item: item,
            imagesCount: imagesCount,
            previewItems: previewItems,
            previewGroup: previewGroup,
            displayMode: .adaptiveGrid(aspectRatio: tileWidth / max(tileHeight, 1))
        )

        return Group {
            if let accessibilityName {
                tile.accessibilityLabel(
                    "查看第 \(item.index + 1) 张\(accessibilityName)，共 \(imagesCount) 张"
                )
            } else {
                tile
            }
        }
        .frame(width: tileWidth, height: tileHeight)
    }
}

import SwiftUI

enum DynamicImageCellDisplayMode {
    case single
    case longImage(cornerRadius: CGFloat)
    case square(cornerRadius: CGFloat)
    case hero(aspectRatio: CGFloat, cornerRadius: CGFloat)
    case fixedHeight(height: CGFloat, cornerRadius: CGFloat)
}

extension DynamicImageCellDisplayMode {
    var cornerRadius: CGFloat {
        switch self {
        case .single:
            return 8
        case .longImage(let cornerRadius),
             .square(let cornerRadius),
             .hero(_, let cornerRadius),
             .fixedHeight(_, let cornerRadius):
            return cornerRadius
        }
    }

    var thumbnailContentMode: ZoomyImageContentMode {
        switch self {
        case .fixedHeight:
            return .fit
        case .single, .longImage, .square, .hero:
            return .fill
        }
    }

    var thumbnailContentAlignment: ZoomyImageContentAlignment {
        switch self {
        case .longImage:
            return .top
        case .single, .square, .hero, .fixedHeight:
            return .center
        }
    }

    func displayAspectRatio(imageAspectRatio: CGFloat) -> CGFloat {
        switch self {
        case .single:
            return imageAspectRatio
        case .longImage:
            return 9 / 16
        case .square:
            return 1
        case .hero(let aspectRatio, _):
            return aspectRatio
        case .fixedHeight:
            return imageAspectRatio
        }
    }

    func thumbnailMaxSide(usesCompactImages: Bool) -> Int {
        switch self {
        case .single, .longImage, .hero:
            return usesCompactImages ? 960 : 1280
        case .square, .fixedHeight:
            return usesCompactImages ? 360 : 420
        }
    }
}

extension DynamicImageCell {
    typealias DisplayMode = DynamicImageCellDisplayMode
}

struct LongImageBadge: View {
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Label("长图", systemImage: "scroll")
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .biliPlayerClearGlass(interactive: false, in: Capsule())
                .accessibilityLabel("长图")
        }
    }
}

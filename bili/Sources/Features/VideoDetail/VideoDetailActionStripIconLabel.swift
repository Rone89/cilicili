import SwiftUI

struct VideoDetailActionStripIconLabel: View {
    let systemImage: String
    let foregroundStyle: Color
    let side: CGFloat
    let iconSize: CGFloat

    init(
        systemImage: String,
        foregroundStyle: Color,
        side: CGFloat = VideoDetailActionStrip.Metrics.actionLabelSide,
        iconSize: CGFloat = VideoDetailActionStrip.Metrics.iconSize
    ) {
        self.systemImage = systemImage
        self.foregroundStyle = foregroundStyle
        self.side = side
        self.iconSize = iconSize
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .frame(
                width: side,
                height: side
            )
            .foregroundStyle(foregroundStyle)
            .contentShape(Circle())
    }
}

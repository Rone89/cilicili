import SwiftUI

extension View {
    func initialPageMenuPlaceholderBackground() -> some View {
        frame(height: VideoDetailSkeletonStyle.pageMenuHeight)
            .background(
                VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.pageMenuFillOpacity),
                in: RoundedRectangle(
                    cornerRadius: VideoDetailSkeletonStyle.pageMenuCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VideoDetailSkeletonStyle.pageMenuCornerRadius,
                    style: .continuous
                )
                .stroke(
                    Color.secondary.opacity(VideoDetailSkeletonStyle.pageMenuStrokeOpacity),
                    lineWidth: VideoDetailSkeletonStyle.pageMenuStrokeWidth
                )
            }
    }
}

import SwiftUI

extension LiveRoomContentView {
    func detailScrollPage(_ viewModel: LiveRoomViewModel, layoutWidth: CGFloat) -> some View {
        let horizontalPadding: CGFloat = 12
        let contentWidth = max(layoutWidth - horizontalPadding * 2, 0)

        return VStack(alignment: .leading, spacing: 10) {
            liveDetailControls(viewModel, contentWidth: contentWidth)
                .padding(.horizontal, horizontalPadding)
        }
        .padding(.top, 8)
        .frame(width: layoutWidth, alignment: .top)
        .background(VideoDetailTheme.background)
    }

    func liveDetailControls(_ viewModel: LiveRoomViewModel, contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveRoomInfoBlock(viewModel: viewModel)
            liveActionStrip(viewModel, contentWidth: contentWidth)
            liveInlineControlStrip(viewModel)
            liveStatusNotice(viewModel)
        }
        .frame(width: contentWidth, alignment: .leading)
    }
}

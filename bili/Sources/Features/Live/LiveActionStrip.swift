import SwiftUI

struct LiveActionStrip: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    let contentWidth: CGFloat

    private let columnSpacing: CGFloat = 4

    private var columnWidth: CGFloat {
        max((contentWidth - columnSpacing * 4) / 5, 1)
    }

    var body: some View {
        GlassEffectContainer(spacing: columnSpacing) {
            HStack(spacing: columnSpacing) {
                LiveOwnerAvatar(viewModel: viewModel)
                    .frame(width: columnWidth, height: 25)

                LiveFollowButton(viewModel: viewModel)
                    .frame(width: columnWidth, height: 25)

                LiveActionContent(
                    title: viewModel.onlineActionText,
                    systemImage: "person.2.fill",
                    foregroundStyle: .primary
                )
                .frame(width: columnWidth, height: 25)

                LiveActionContent(
                    title: viewModel.areaActionText,
                    systemImage: "tag.fill",
                    foregroundStyle: .primary
                )
                .frame(width: columnWidth, height: 25)

                LiveActionContent(
                    title: viewModel.isLive ? "直播中" : "未开播",
                    systemImage: viewModel.isLive ? "dot.radiowaves.left.and.right" : "pause.circle",
                    foregroundStyle: viewModel.isLive ? .pink : .secondary
                )
                .frame(width: columnWidth, height: 25)
            }
        }
        .frame(width: contentWidth, height: 25, alignment: .center)
    }
}

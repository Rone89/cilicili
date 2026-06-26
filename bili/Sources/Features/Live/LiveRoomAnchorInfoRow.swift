import SwiftUI

struct LiveRoomAnchorInfoRow: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarRemoteImage(urlString: viewModel.anchorFace, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                LiveRoomAnchorNameRow(
                    anchorName: viewModel.anchorName,
                    isFollowingAnchor: viewModel.isFollowingAnchor
                )

                LiveRoomAnchorStatusRow(
                    isLive: viewModel.isLive,
                    onlineText: viewModel.onlineText
                )
            }

            Spacer(minLength: 0)
        }
    }
}

private struct LiveRoomAnchorNameRow: View {
    let anchorName: String
    let isFollowingAnchor: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(anchorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isFollowingAnchor {
                Text("已关注")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.pink.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

private struct LiveRoomAnchorStatusRow: View {
    let isLive: Bool
    let onlineText: String

    var body: some View {
        HStack(spacing: 8) {
            Label(
                isLive ? "直播中" : "未开播",
                systemImage: isLive ? "dot.radiowaves.left.and.right" : "pause.circle"
            )
            .foregroundStyle(isLive ? .pink : .secondary)

            Text(onlineText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

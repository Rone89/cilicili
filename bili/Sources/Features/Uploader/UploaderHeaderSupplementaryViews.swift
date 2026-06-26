import SwiftUI

struct UploaderSignatureText: View {
    let sign: String?

    var body: some View {
        if let sign, !sign.isEmpty {
            Text(sign)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct UploaderFollowMessage: View {
    let message: String?
    let isFollowing: Bool

    var body: some View {
        if let message, !message.isEmpty {
            Label(message, systemImage: isFollowing ? "checkmark.circle" : "info.circle")
                .font(.caption)
                .foregroundStyle(isFollowing ? Color.pink : Color.secondary)
        }
    }
}

struct UploaderStatsRow: View {
    let viewModel: UploaderViewModel
    let card: UploaderCard?

    var body: some View {
        HStack(spacing: 14) {
            UploaderStatItem(title: "粉丝", value: viewModel.followerCount ?? card?.fans)
            UploaderStatItem(title: "关注", value: card?.attention)
            UploaderStatItem(title: "获赞", value: viewModel.profile?.likeNum)
            UploaderStatItem(title: "投稿", value: viewModel.profile?.archiveCount)
        }
    }
}

private struct UploaderStatItem: View {
    let title: String
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BiliFormatters.compactCount(value))
                .font(.subheadline.weight(.bold))

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

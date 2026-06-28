import SwiftUI

struct LiveRoomDescriptionSheet: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    private var displayDescription: String {
        viewModel.descriptionText ?? "这个直播间暂时没有简介。"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(viewModel.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LiveRoomDescriptionAnchorRow(viewModel: viewModel)
                    LiveRoomDescriptionMetadata(viewModel: viewModel)

                    Divider()

                    Text(displayDescription)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .navigationTitle("直播简介")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct LiveRoomDescriptionMetadata: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let areaText = viewModel.areaText {
                Label(areaText, systemImage: "tag")
            }
            Label(viewModel.onlineText, systemImage: "person.2")
            if let liveTimeText = viewModel.liveTimeText {
                Label(liveTimeText, systemImage: "clock")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveRoomDescriptionAnchorRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        HStack(spacing: 10) {
            AvatarRemoteImage(urlString: viewModel.anchorFace, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                LiveRoomDescriptionAnchorName(viewModel: viewModel)

                Text(viewModel.isLive ? "直播中" : "未开播")
                    .font(.caption)
                    .foregroundStyle(viewModel.isLive ? appTintColor : .secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("主播 \(viewModel.anchorName)")
    }
}

private struct LiveRoomDescriptionAnchorName: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        HStack(spacing: 6) {
            Text(viewModel.anchorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if viewModel.isFollowingAnchor {
                Text("已关注")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(appTintColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(appTintColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

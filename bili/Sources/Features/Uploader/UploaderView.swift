import SwiftUI
import Combine

private struct UploaderContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct UploaderView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let owner: VideoOwner

    @StateObject private var holder = UploaderViewModelHolder()
    @State private var contentWidth: CGFloat = 0

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .task {
                        holder.configure(owner: owner, api: dependencies.api)
                    }
            }
        }
        .navigationTitle(owner.name)
        .navigationBarTitleDisplayMode(.inline)
        .hidesRootTabBarOnPush()
    }

    private func content(_ viewModel: UploaderViewModel) -> some View {
        ScrollView {
            contentWidthReader

            VStack(alignment: .leading, spacing: 18) {
                header(viewModel)

                Text("投稿")
                    .font(.headline)
                    .padding(.horizontal)

                if viewModel.videos.isEmpty && viewModel.state.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载投稿")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else if viewModel.videos.isEmpty {
                    EmptyStateView(title: "暂无投稿", systemImage: "film", message: "下拉刷新后再试。")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.videos) { video in
                            VideoRouteLink(video) {
                                VideoCardView(
                                    video: video,
                                    showsCoverViewCountBadge: false,
                                    fixedCoverSize: gridCoverSize
                                )
                            }
                            .task {
                                await viewModel.loadMoreIfNeeded(current: video)
                            }
                        }

                        if viewModel.state.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .gridCellColumns(2)
                                .padding()
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
        .onPreferenceChange(UploaderContentWidthPreferenceKey.self) { width in
            let roundedWidth = width.rounded(.down)
            guard abs(roundedWidth - contentWidth) > 0.5 else { return }
            contentWidth = roundedWidth
        }
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.videos.isEmpty {
                ErrorStateView(title: "UP 主加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .background(.background.opacity(0.95))
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    private var contentWidthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: UploaderContentWidthPreferenceKey.self, value: proxy.size.width)
        }
        .frame(height: 0)
    }

    private var gridCoverSize: CGSize? {
        let gridHorizontalPadding: CGFloat = 24
        let columnSpacing: CGFloat = 12
        let width = (contentWidth - gridHorizontalPadding - columnSpacing) / 2
        guard width > 0 else { return nil }
        return CGSize(width: width, height: width * 9 / 16)
    }

    private func header(_ viewModel: UploaderViewModel) -> some View {
        let card = viewModel.profile?.card

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                AvatarRemoteImage(urlString: card?.face ?? owner.face, pixelSize: 160) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(card?.name ?? owner.name)
                        .font(.title3.weight(.bold))
                    Text("UID \(card?.mid ?? owner.mid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                followButton(viewModel)
            }

            if let sign = card?.sign, !sign.isEmpty {
                Text(sign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = viewModel.followMessage, !message.isEmpty {
                Label(message, systemImage: viewModel.isFollowing ? "checkmark.circle" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(viewModel.isFollowing ? Color.pink : Color.secondary)
            }

            HStack(spacing: 14) {
                statItem("粉丝", value: viewModel.followerCount ?? card?.fans)
                statItem("关注", value: card?.attention)
                statItem("获赞", value: viewModel.profile?.likeNum)
                statItem("投稿", value: viewModel.profile?.archiveCount)
            }
        }
        .padding()
        .biliGlassEffect(
            tint: Color(.secondarySystemBackground).opacity(0.18),
            interactive: false,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .padding(.horizontal, 12)
    }

    private func followButton(_ viewModel: UploaderViewModel) -> some View {
        Button {
            Task {
                let didSucceed = await viewModel.toggleFollow()
                if didSucceed {
                    Haptics.success()
                } else {
                    Haptics.light()
                }
            }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isMutatingFollow {
                    ProgressView()
                        .controlSize(.small)
                        .tint(viewModel.isFollowing ? .secondary : .white)
                } else {
                    Image(systemName: viewModel.isFollowing ? "checkmark" : "plus")
                        .font(.caption.weight(.bold))
                }

                Text(viewModel.isFollowing ? "已关注" : "关注")
                    .font(.subheadline.weight(.bold))
            }
            .frame(minWidth: 82, minHeight: 34)
            .padding(.horizontal, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(viewModel.isFollowing ? Color(.tertiarySystemFill) : Color.pink)
            }
            .foregroundStyle(viewModel.isFollowing ? Color.secondary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isMutatingFollow || owner.mid <= 0)
    }

    private func statItem(_ title: String, value: Int?) -> some View {
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

@MainActor
final class UploaderViewModelHolder: ObservableObject {
    @Published var viewModel: UploaderViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: UploaderRenderSnapshot?

    func configure(owner: VideoOwner, api: BiliAPIClient) {
        if viewModel == nil {
            let viewModel = UploaderViewModel(seedOwner: owner, api: api)
            self.viewModel = viewModel
            lastSnapshot = UploaderRenderSnapshot(viewModel)
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self, weak viewModel] in
                    guard let self, let viewModel else { return }
                    let snapshot = UploaderRenderSnapshot(viewModel)
                    guard snapshot != self.lastSnapshot else { return }
                    self.lastSnapshot = snapshot
                    self.objectWillChange.send()
                }
            }
        }
    }
}

private struct UploaderRenderSnapshot: Equatable {
    let state: LoadingState
    let profileRevision: Int
    let videosRevision: Int
    let videoCount: Int
    let firstVideoID: String?
    let lastVideoID: String?
    let isFollowing: Bool
    let followerCount: Int?
    let isMutatingFollow: Bool
    let followMessage: String?

    init(_ viewModel: UploaderViewModel) {
        state = viewModel.state
        profileRevision = viewModel.profileRevision
        videosRevision = viewModel.videosRevision
        videoCount = viewModel.videos.count
        firstVideoID = viewModel.videos.first?.id
        lastVideoID = viewModel.videos.last?.id
        isFollowing = viewModel.isFollowing
        followerCount = viewModel.followerCount
        isMutatingFollow = viewModel.isMutatingFollow
        followMessage = viewModel.followMessage
    }
}

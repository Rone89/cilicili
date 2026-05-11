import SwiftUI
import Combine

struct UploaderView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let owner: VideoOwner

    @StateObject private var holder = UploaderViewModelHolder()

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
                                VideoCardView(video: video)
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

    private func header(_ viewModel: UploaderViewModel) -> some View {
        let card = viewModel.profile?.card

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                AsyncImage(url: (card?.face ?? owner.face).flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 160)) }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
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
            }

            if let sign = card?.sign, !sign.isEmpty {
                Text(sign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                statItem("粉丝", value: viewModel.profile?.follower ?? card?.fans)
                statItem("关注", value: card?.attention)
                statItem("获赞", value: viewModel.profile?.likeNum)
                statItem("投稿", value: viewModel.profile?.archiveCount)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
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

    func configure(owner: VideoOwner, api: BiliAPIClient) {
        if viewModel == nil {
            let viewModel = UploaderViewModel(seedOwner: owner, api: api)
            self.viewModel = viewModel
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}

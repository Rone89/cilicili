import SwiftUI

struct UploaderView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let owner: VideoOwner
    let allowsPullToRefresh: Bool
    let showsToolbarRefreshButton: Bool

    @StateObject private var holder = UploaderViewModelHolder()

    init(
        owner: VideoOwner,
        allowsPullToRefresh: Bool = true,
        showsToolbarRefreshButton: Bool = false
    ) {
        self.owner = owner
        self.allowsPullToRefresh = allowsPullToRefresh
        self.showsToolbarRefreshButton = showsToolbarRefreshButton
    }

    var body: some View {
        content
    }

    private var content: some View {
        Group {
            if let viewModel = holder.viewModel {
                UploaderContentView(
                    owner: owner,
                    viewModel: viewModel,
                    allowsPullToRefresh: allowsPullToRefresh,
                    showsToolbarRefreshButton: showsToolbarRefreshButton
                )
            } else {
                UploaderInitialLoadingView()
            }
        }
        .task(id: owner.mid) {
            holder.configure(owner: owner, api: dependencies.api)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UploaderInitialLoadingView: View {
    var body: some View {
        InitialContentLoadingView(title: "正在加载 UP 主主页")
        .allowsHitTesting(false)
        .accessibilityLabel("正在加载 UP 主主页")
    }
}

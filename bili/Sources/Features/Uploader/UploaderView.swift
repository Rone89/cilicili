import SwiftUI

struct UploaderView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    let owner: VideoOwner
    let allowsPullToRefresh: Bool
    let horizontalInset: CGFloat?

    @StateObject private var holder = UploaderViewModelHolder()

    init(
        owner: VideoOwner,
        allowsPullToRefresh: Bool = true,
        horizontalInset: CGFloat? = nil
    ) {
        self.owner = owner
        self.allowsPullToRefresh = allowsPullToRefresh
        self.horizontalInset = horizontalInset
    }

    var body: some View {
        content
            .nativeBottomScrollEdgeBlurVisibility(isHidden: false)
            .toolbar(.hidden, for: .tabBar)
    }

    private var content: some View {
        Group {
            if let viewModel = holder.viewModel, viewModel.isCurrentViewerContext {
                UploaderSpaceContentView(
                    owner: owner, viewModel: viewModel,
                    allowsPullToRefresh: allowsPullToRefresh,
                    horizontalInset: horizontalInset ?? libraryStore.standardPageHorizontalInset
                )
            } else {
                UploaderInitialLoadingView()
            }
        }
        .id(configurationID)
        .task(id: configurationID) {
            holder.configure(owner: owner, api: dependencies.api)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var configurationID: String {
        // Observe session changes even though the authoritative request context is owned by the API.
        _ = sessionStore.accountConfigurationVersion
        let identity = UploaderSpaceRequestIdentity(dependencies.api.requestSnapshot())
        return "space-\(owner.mid)-\(identity.accountMID ?? 0)-\(identity.credentialVersion)-\(identity.isLoggedIn)-\(identity.isPurposeEnabled)-\(identity.guestModeEnabled)"
    }
}

private struct UploaderInitialLoadingView: View {
    var body: some View {
        InitialContentLoadingView(title: "正在加载 UP 主主页")
        .allowsHitTesting(false)
        .accessibilityLabel("正在加载 UP 主主页")
    }
}

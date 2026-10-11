import SwiftUI

struct UploaderView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
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
            .nativeBottomScrollEdgeBlurVisibility(isHidden: true)
            .toolbar(.hidden, for: .tabBar)
    }

    private var content: some View {
        Group {
            if let viewModel = holder.viewModel,
               viewModel.enhancementEnabled == libraryStore.personalSpaceEnhancementExperimentEnabled,
               viewModel.isCurrentViewerContext {
                if viewModel.enhancementEnabled {
                    UploaderEnhancedContentView(
                        owner: owner, viewModel: viewModel,
                        allowsPullToRefresh: allowsPullToRefresh,
                        showsToolbarRefreshButton: showsToolbarRefreshButton
                    )
                } else {
                    UploaderContentView(
                        owner: owner,
                        viewModel: viewModel,
                        allowsPullToRefresh: allowsPullToRefresh,
                        showsToolbarRefreshButton: showsToolbarRefreshButton
                    )
                }
            } else {
                UploaderInitialLoadingView()
            }
        }
        .id(configurationID)
        .task(id: configurationID) {
            holder.configure(owner: owner, api: dependencies.api,
                             enhancementEnabled: libraryStore.personalSpaceEnhancementExperimentEnabled)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var configurationID: String {
        guard libraryStore.personalSpaceEnhancementExperimentEnabled else { return "legacy-\(owner.mid)" }
        // Observe session changes even though the authoritative request context is owned by the API.
        _ = sessionStore.accountConfigurationVersion
        let identity = UploaderSpaceRequestIdentity(dependencies.api.requestSnapshot())
        return "enhanced-\(owner.mid)-\(identity.accountMID ?? 0)-\(identity.credentialVersion)-\(identity.isLoggedIn)-\(identity.isPurposeEnabled)-\(identity.guestModeEnabled)"
    }
}

private struct UploaderInitialLoadingView: View {
    var body: some View {
        InitialContentLoadingView(title: "正在加载 UP 主主页")
        .allowsHitTesting(false)
        .accessibilityLabel("正在加载 UP 主主页")
    }
}

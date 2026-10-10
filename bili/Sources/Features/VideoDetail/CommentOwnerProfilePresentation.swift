import SwiftUI

private struct CommentOwnerProfileRoute: Identifiable {
    let owner: VideoOwner

    var id: Int { owner.mid }
}

struct CommentOwnerProfileNavigationContainer<Content: View>: View {
    @Environment(\.commentSheetToolbarConfiguration) private var toolbarConfiguration
    @Environment(\.openAppURLAction) private var openAppURL
    @State private var profileRoute: CommentOwnerProfileRoute?
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .environment(\.openVideoOwnerRouteAction, openProfile)
                .environment(\.openAppURLAction, openCommentURL)
                .environment(\.openVideoAction, nil)
                .environment(\.openLiveRoomAction, nil)
                .environment(\.openPgcSeasonRouteAction, nil)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("返回", systemImage: "chevron.left", action: toolbarConfiguration.onDismiss)
                            .tint(.primary)
                            .accessibilityLabel("返回")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("刷新", systemImage: "arrow.clockwise", action: toolbarConfiguration.onRefresh)
                            .tint(.primary)
                            .accessibilityLabel("刷新评论")
                    }
                }
        }
        .toolbar(.visible, for: .navigationBar)
        .nativeBottomScrollEdgeBlurVisibility(isHidden: true)
        .sheet(item: $profileRoute) { route in
            NavigationStack {
                UploaderView(owner: route.owner)
                    .environment(\.openVideoOwnerRouteAction, nil)
                    .environment(\.openVideoAction, nil)
                    .environment(\.openLiveRoomAction, nil)
                    .environment(\.openPgcSeasonRouteAction, nil)
                    .videoDestinations()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭", systemImage: "xmark") {
                                profileRoute = nil
                            }
                            .tint(.primary)
                            .accessibilityIdentifier("comment.profile.close")
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("comment.profile.sheet")
        }
    }

    private func openProfile(_ owner: VideoOwner) {
        guard owner.mid > 0 else { return }

        profileRoute = CommentOwnerProfileRoute(owner: owner)
    }

    private func openCommentURL(_ url: URL) {
        if let owner = AppLinkRouter.userOwner(from: url) {
            openProfile(owner)
        } else {
            openAppURL?(url)
        }
    }
}

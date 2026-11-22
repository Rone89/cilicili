import SwiftUI

private struct CommentOwnerProfileRoute: Identifiable {
    let owner: VideoOwner

    var id: Int { owner.mid }
}

struct CommentOwnerProfileNavigationContainer<Content: View>: View {
    @Environment(\.commentSheetToolbarConfiguration) private var toolbarConfiguration
    @Environment(\.videoDetailSplitSheetDismiss) private var splitSheetDismiss
    @Environment(\.openAppURLAction) private var openAppURL
    @State private var profileRoute: CommentOwnerProfileRoute?
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if splitSheetDismiss != nil {
                // Hosted inline inside the landscape split right column: avoid embedding a nested
                // NavigationStack inside the parent VideoDetail NavigationStack destination.
                VStack(spacing: 0) {
                    inlineSplitHeader
                    commentContent
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(.clear)
            } else {
                NavigationStack {
                    commentContent
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
            }
        }
        .nativeBottomScrollEdgeBlurVisibility(isHidden: true)
        .sheet(item: $profileRoute) { route in
            NavigationStack {
                UploaderView(owner: route.owner, horizontalInset: 20)
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

    private var commentContent: some View {
        content()
            .environment(\.openVideoOwnerRouteAction, openProfile)
            .environment(\.openAppURLAction, openCommentURL)
            .environment(\.openVideoAction, nil)
            .environment(\.openLiveRoomAction, nil)
            .environment(\.openPgcSeasonRouteAction, nil)
    }

    private var inlineSplitHeader: some View {
        HStack {
            Button(action: toolbarConfiguration.onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("返回")

            Spacer()

            Button(action: toolbarConfiguration.onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("刷新评论")
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
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

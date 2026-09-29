import SwiftUI

struct DynamicFeedSkeletonScrollContent: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        let horizontalInset = libraryStore.standardPageHorizontalInset

        ScrollView {
            DynamicFeedSkeletonList()
                .padding(.horizontal, horizontalInset)
        }
        .nativeTopScrollEdgeEffect()
    }
}

struct DynamicFeedSkeletonList: View {
    var body: some View {
        SkeletonLoadingContainer {
            LazyVStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    DynamicFeedSkeletonCard()

                    if index != 2 {
                        Divider()
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct DynamicFeedErrorOverlay: View {
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool

    var body: some View {
        Group {
            if isLoggedIn,
               case .failed(let message) = viewModel.state,
               viewModel.items.isEmpty {
                ErrorStateView(title: "动态加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .background(.background.opacity(0.96))
            }
        }
    }
}

struct DynamicLoginEmptyState: View {
    var body: some View {
        EmptyStateView(
            title: "暂无动态",
            systemImage: "sparkles",
            message: "登录后会显示你关注 UP 的动态。"
        )
    }
}

struct DynamicFeedEmptyState: View {
    var body: some View {
        EmptyStateView(
            title: "暂无动态",
            systemImage: "sparkles",
            message: "登录后会显示你关注 UP 的动态。"
        )
    }
}

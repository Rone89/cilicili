import SwiftUI

struct DynamicCommentsSheet: View {
    let item: DynamicFeedItem
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var viewModel: DynamicCommentsViewModel
    @StateObject private var runtimeSettings = DynamicCommentsRuntimeSettingsStore()
    @State private var replySheetComment: Comment?

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        _viewModel = StateObject(wrappedValue: DynamicCommentsViewModel(item: item, api: api))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DynamicCommentsSheetContent(item: item, viewModel: viewModel) { comment in
                    replySheetComment = comment
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect(hidesRootNavigationTitle: false)
            .task {
                runtimeSettings.bind(dependencies.libraryStore)
                viewModel.setBlocksGoodsComments(runtimeSettings.blocksGoodsComments)
                await viewModel.loadInitial()
            }
        }
        .onChange(of: runtimeSettings.blocksGoodsComments) { _, isEnabled in
            viewModel.setBlocksGoodsComments(isEnabled)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $replySheetComment) { comment in
            DynamicCommentRepliesSheet(rootComment: comment, replyStore: viewModel.replyStore)
        }
    }
}

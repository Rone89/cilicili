import Foundation
import SwiftUI

struct VideoDescriptionSheet: View {
    @ObservedObject var store: VideoDetailDescriptionRenderStore
    let actions: VideoDescriptionSheetActions

    init(
        store: VideoDetailDescriptionRenderStore,
        toggleFollow: @escaping () async -> Void
    ) {
        self.store = store
        actions = VideoDescriptionSheetActions(toggleFollow: toggleFollow)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VideoDescriptionSheetContent(
                    store: store,
                    toggleFollow: actions.toggleFollowAction
                )
            }
            .navigationTitle("视频简介")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

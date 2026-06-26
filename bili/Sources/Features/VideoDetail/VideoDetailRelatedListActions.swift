import Foundation

struct VideoDetailRelatedListActions {
    let beginPreload: (VideoItem) -> Void

    func handleRowAppear(_ item: VideoDetailRelatedDisplayItem) {
        beginPreload(item.video)
    }
}

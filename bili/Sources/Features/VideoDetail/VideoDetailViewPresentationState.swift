import Foundation

struct VideoDetailViewPresentationState {
    var selectedContentTab: VideoDetailContentTab = .detail
    var replySheetComment: Comment?
    var isShowingDanmakuSettings = false
    var isShowingFavoriteFolders = false
    var isShowingNetworkDiagnostics = false
    var isClosingDetail = false
}

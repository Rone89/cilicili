import SwiftUI

struct VideoDetailPlaybackSceneBindings {
    let selectedContentTab: Binding<VideoDetailContentTab>
    let replySheetComment: Binding<Comment?>
    let isShowingDanmakuSettings: Binding<Bool>
    let isShowingFavoriteFolders: Binding<Bool>
    let isShowingNetworkDiagnostics: Binding<Bool>

    var sheetState: VideoDetailSheetState {
        VideoDetailSheetState(
            replySheetComment: replySheetComment,
            isShowingFavoriteFolders: isShowingFavoriteFolders,
            isShowingDanmakuSettings: isShowingDanmakuSettings,
            isShowingNetworkDiagnostics: isShowingNetworkDiagnostics
        )
    }
}

import SwiftUI

struct VideoDetailSheetState {
    var replySheetComment: Binding<Comment?>
    var isShowingFavoriteFolders: Binding<Bool>
    var isShowingDanmakuSettings: Binding<Bool>
    var isShowingNetworkDiagnostics: Binding<Bool>
}

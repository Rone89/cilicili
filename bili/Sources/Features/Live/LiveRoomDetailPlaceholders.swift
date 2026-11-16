import SwiftUI

struct LiveRoomInitialPlaceholder: View {
    let room: LiveRoom

    var body: some View {
        LivePlayerLoadingPlaceholder(
            title: room.title.nilIfEmpty ?? "正在进入直播间",
            subtitle: room.uname.nilIfEmpty ?? "准备直播信息"
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VideoDetailTheme.background)
        .overlay(alignment: .top) {
            VideoDetailStatusBarBackdrop(isHidden: false)
        }
    }
}

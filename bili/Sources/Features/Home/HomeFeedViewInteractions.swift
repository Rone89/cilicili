import SwiftUI

extension View {
    func homeVisibleVideoFrame(for video: VideoItem, index: Int) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HomeVisibleVideoFramePreferenceKey.self,
                    value: [
                        HomeVisibleVideoFrame(
                            bvid: video.bvid,
                            index: index,
                            frame: proxy.frame(in: .global)
                        )
                    ]
                )
            }
        }
    }

    @ViewBuilder
    func homeLoadMoreTask(
        if shouldAttachTask: Bool,
        id: String,
        action: @escaping () async -> Void
    ) -> some View {
        if shouldAttachTask {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}

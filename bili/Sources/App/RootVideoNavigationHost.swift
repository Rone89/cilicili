import SwiftUI

struct RootVideoNavigationHost: View {
    @Binding var path: NavigationPath
    let isClosingVideo: Bool
    let onRequestClose: () -> Void
    let onPopOne: () -> Void
    let onCancelledClose: () -> Void
    let onCompletedClose: () -> Void
    let onPathEmptied: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            Color.clear
                .ignoresSafeArea()
                .background(VideoNavigationHostTransparency(suppressesNavigationBar: true))
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: VideoItem.self) { video in
                    VideoDetailView(
                        seedVideo: video,
                        hidesRootTabBar: false,
                        onRequestClose: onRequestClose,
                        onPopOne: onPopOne
                    )
                    .id(video.id)
                }
                .navigationDestination(for: VideoOwner.self) { owner in
                    UploaderView(owner: owner)
                }
                .navigationDestination(for: LiveRoom.self) { room in
                    LiveRoomDetailView(seedRoom: room)
                }
        }
        .background(VideoNavigationHostTransparency(suppressesNavigationBar: true))
        .background(VideoNavigationTransitionObserver(isClosing: isClosingVideo) { cancelled in
            if cancelled {
                onCancelledClose()
            } else {
                onCompletedClose()
            }
        })
        .onChange(of: path) { _, newPath in
            guard newPath.isEmpty else { return }
            onPathEmptied()
        }
    }
}

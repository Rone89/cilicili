import SwiftUI

struct LiveRoomDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    let seedRoom: LiveRoom
    var usesTransparentNavigationBar = false
    @StateObject private var holder = LiveRoomViewModelHolder()

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: .constant(false),
            background: VideoDetailTheme.background,
            hidesBackButton: true,
            statusBarStyle: .lightContent,
            performanceContext: .live(seedRoom),
            lifecycleActions: pageLifecycleActions
        ) {
            PlaybackDetailLoadedStatePage(
                holder.viewModel,
                performanceContext: .live(seedRoom)
            ) { viewModel in
                LiveRoomShellRepresentable(
                    viewModel: viewModel,
                    usesTransparentNavigationBar: usesTransparentNavigationBar,
                    onNavigateBack: { dismiss() }
                )
                .ignoresSafeArea()
            } initialContent: {
                LiveRoomInitialPlaceholder(room: seedRoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .playbackUnderTransparentNavigationBar(usesTransparentNavigationBar)
            }
        }
        .toolbarVisibility(usesTransparentNavigationBar ? .visible : .hidden, for: .navigationBar)
        .task(id: seedRoom.id) {
            configureAndStartPlaybackIfNeeded()
        }
    }

    private var pageLifecycleActions: PlaybackDetailPageLifecycleActions {
        PlaybackDetailPageLifecycleActions(
            onAppear: {
                holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
            },
            onScenePhaseChanged: { phase in
                guard let viewModel = holder.viewModel else { return }
                switch phase {
                case .active:
                    viewModel.resumeLiveDanmakuIfNeeded()
                case .background:
                    viewModel.suspendLiveDanmaku()
                default:
                    break
                }
            },
            onDisappear: {
                holder.viewModel?.stopPlaybackForNavigation()
            }
        )
    }

    private func configureAndStartPlaybackIfNeeded() {
        holder.configure(
            room: seedRoom,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore
        )
        holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
    }

}

import Combine
import SwiftUI

struct PlaybackPosterOverlay: View {
    let video: VideoItem
    let playerViewModel: PlayerStateViewModel
    let dimOpacity: Double
    let showsLoader: Bool
    @StateObject private var state = PlaybackPosterOverlayState()

    var body: some View {
        let snapshot = state.snapshot
        ZStack {
            if snapshot.shouldShowPoster {
                PlayerLoadingPlaceholder(
                    progress: snapshot.loadingProgress,
                    message: snapshot.loadingMessage,
                    isFinishing: snapshot.isFinishing
                )
                .background(Color.black.opacity(dimOpacity))
                .compositingGroup()
                .clipped()
                .transition(
                    .asymmetric(
                        insertion: .opacity,
                        removal: .opacity.animation(.smooth(duration: 0.30))
                    )
                )
                .animation(.smooth(duration: 0.30), value: snapshot.isPlaybackSurfaceReady)
                .animation(.smooth(duration: 0.18), value: snapshot.isFinishing)
                .animation(.smooth(duration: 0.20), value: snapshot.loadingProgress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            state.bind(playerViewModel: playerViewModel)
        }
        .onChange(of: ObjectIdentifier(playerViewModel)) { _, _ in
            state.bind(playerViewModel: playerViewModel)
        }
    }
}

private struct PlaybackPosterSnapshot: Equatable {
    var isPlaybackSurfaceReady = false
    var errorMessage: String?
    var loadingProgress = 0.08
    var isBuffering = false

    @MainActor
    init(playerViewModel: PlayerStateViewModel? = nil) {
        guard let playerViewModel else { return }
        isPlaybackSurfaceReady = playerViewModel.isPlaybackSurfaceReady
        errorMessage = playerViewModel.errorMessage
        loadingProgress = playerViewModel.loadingProgress
        isBuffering = playerViewModel.isBuffering
    }

    var shouldShowPoster: Bool {
        !isPlaybackSurfaceReady && errorMessage == nil
    }

    var isFinishing: Bool {
        loadingProgress >= 0.98
    }

    var loadingMessage: String {
        if isBuffering {
            return "补充缓冲"
        }
        if loadingProgress >= 0.86 {
            return "等待首帧"
        }
        return "准备播放"
    }
}

@MainActor
private final class PlaybackPosterOverlayState: ObservableObject {
    @Published private(set) var snapshot: PlaybackPosterSnapshot
    private weak var playerViewModel: PlayerStateViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var snapshotRefreshTask: Task<Void, Never>?

    init(playerViewModel: PlayerStateViewModel? = nil) {
        snapshot = PlaybackPosterSnapshot(playerViewModel: playerViewModel)
    }

    func bind(playerViewModel: PlayerStateViewModel) {
        guard self.playerViewModel !== playerViewModel else {
            refreshSnapshot(from: playerViewModel)
            return
        }
        cancellables.removeAll()
        self.playerViewModel = playerViewModel
        refreshSnapshot(from: playerViewModel)

        let refresh: () -> Void = { [weak self] in
            self?.scheduleSnapshotRefresh()
        }

        playerViewModel.$isPlaybackSurfaceReady
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        playerViewModel.$errorMessage
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        playerViewModel.$loadingProgress
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { _ in refresh() }
            .store(in: &cancellables)

        playerViewModel.$isBuffering
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)
    }

    private func scheduleSnapshotRefresh() {
        guard snapshotRefreshTask == nil else { return }
        snapshotRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, let playerViewModel = self.playerViewModel, !Task.isCancelled else { return }
            self.snapshotRefreshTask = nil
            self.refreshSnapshot(from: playerViewModel)
        }
    }

    private func refreshSnapshot(from playerViewModel: PlayerStateViewModel) {
        let nextSnapshot = PlaybackPosterSnapshot(playerViewModel: playerViewModel)
        guard nextSnapshot != snapshot else { return }
        snapshot = nextSnapshot
    }

    deinit {
        snapshotRefreshTask?.cancel()
    }
}

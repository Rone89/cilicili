import Combine
import SwiftUI

struct VideoDetailDanmakuOverlay: View {
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let clock: PlayerPlaybackClock
    let usesLandscapePlaybackChrome: Bool
    let onPlaybackTime: (TimeInterval, Bool) -> Void
    @StateObject private var state = VideoDetailDanmakuOverlayState()

    var body: some View {
        let snapshot = state.snapshot

        DanmakuOverlayView(
            items: snapshot.items,
            itemsRevision: snapshot.itemsRevision,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            isEnabled: snapshot.isEnabled,
            hasPresentedPlayback: snapshot.hasPresentedPlayback,
            isLoadShedding: snapshot.isLoadShedding,
            settings: snapshot.settings,
            topInset: usesLandscapePlaybackChrome ? 28 : 8,
            bottomInset: usesLandscapePlaybackChrome ? 84 : 54,
            playbackClock: clock,
            onPlaybackTime: onPlaybackTime
        )
        .padding(.horizontal, usesLandscapePlaybackChrome ? 18 : 4)
        .onAppear {
            state.bind(store: store, playerViewModel: playerViewModel)
            onPlaybackTime(clock.currentTime, false)
        }
        .onChange(of: ObjectIdentifier(playerViewModel)) { _, _ in
            state.bind(store: store, playerViewModel: playerViewModel)
            onPlaybackTime(clock.currentTime, false)
        }
        .onChange(of: snapshot.isEnabled) { _, isEnabled in
            if isEnabled {
                onPlaybackTime(clock.currentTime, false)
            }
        }
    }
}

@MainActor
private final class VideoDetailDanmakuOverlayState: ObservableObject {
    @Published private(set) var snapshot = VideoDetailDanmakuOverlaySnapshot()

    private weak var store: VideoDetailDanmakuRenderStore?
    private weak var playerViewModel: PlayerStateViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var allItems: [DanmakuItem] = []
    private var sourceItemsRevision = 0
    private var publishedSourceItemsRevision = -1
    private var publishedWindowRange: Range<Int> = 0..<0
    private var lastWindowCenterBucket: Int?
    private let normalWindowLookBehind: TimeInterval = 12
    private let normalWindowLookAhead: TimeInterval = 45
    private let windowRecenterInterval: TimeInterval = 8

    func bind(store: VideoDetailDanmakuRenderStore, playerViewModel: PlayerStateViewModel) {
        guard self.store !== store || self.playerViewModel !== playerViewModel else { return }
        cancellables.removeAll()
        self.store = store
        self.playerViewModel = playerViewModel

        let renderSnapshot = store.snapshot
        allItems = renderSnapshot.items
        sourceItemsRevision = renderSnapshot.itemsRevision
        publishedSourceItemsRevision = -1
        publishedWindowRange = 0..<0
        lastWindowCenterBucket = nil
        updateWindow(around: playerViewModel.playbackClock.currentTime, force: true)
        refreshSnapshot(renderSnapshot: renderSnapshot, playerViewModel: playerViewModel)

        store.$snapshot
            .dropFirst()
            .sink { [weak self, weak playerViewModel] renderSnapshot in
                guard let self else { return }
                self.updateSnapshot {
                    $0.isEnabled = renderSnapshot.isDanmakuEnabled
                    $0.settings = renderSnapshot.effectiveSettings
                }
                guard self.sourceItemsRevision != renderSnapshot.itemsRevision else { return }
                self.allItems = renderSnapshot.items
                self.sourceItemsRevision = renderSnapshot.itemsRevision
                self.lastWindowCenterBucket = nil
                self.updateWindow(
                    around: playerViewModel?.playbackClock.currentTime ?? 0,
                    force: true
                )
            }
            .store(in: &cancellables)

        let recenterInterval = windowRecenterInterval
        playerViewModel.playbackClock.$currentTime
            .map { currentTime in
                Int(max(0, currentTime) / max(recenterInterval, 1))
            }
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] _ in
                guard let self, let playerViewModel else { return }
                self.updateWindow(around: playerViewModel.playbackClock.currentTime, force: false)
            }
            .store(in: &cancellables)

        playerViewModel.$isPlaying
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.updateSnapshot { $0.isPlaying = isPlaying }
            }
            .store(in: &cancellables)

        playerViewModel.$playbackRate
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] rate in
                guard let self else { return }
                let previousLoadShedding = self.snapshot.isLoadShedding
                self.updateSnapshot {
                    $0.playbackRate = rate.rawValue
                    if let playerViewModel {
                        $0.isLoadShedding = Self.loadSheddingState(for: playerViewModel)
                    }
                }
                if let playerViewModel,
                   previousLoadShedding != self.snapshot.isLoadShedding {
                    self.updateWindow(around: playerViewModel.playbackClock.currentTime, force: true)
                }
            }
            .store(in: &cancellables)

        playerViewModel.$isPlaybackSurfaceReady
            .removeDuplicates()
            .sink { [weak self] isPlaybackSurfaceReady in
                self?.updateSnapshot { $0.hasPresentedPlayback = isPlaybackSurfaceReady }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(playerViewModel.$isBuffering, playerViewModel.$isUserSeeking)
            .sink { [weak self, weak playerViewModel] _, _ in
                guard let self, let playerViewModel else { return }
                let previousLoadShedding = self.snapshot.isLoadShedding
                self.updateSnapshot { $0.isLoadShedding = Self.loadSheddingState(for: playerViewModel) }
                if previousLoadShedding != self.snapshot.isLoadShedding {
                    self.updateWindow(around: playerViewModel.playbackClock.currentTime, force: true)
                }
            }
            .store(in: &cancellables)
    }

    private func refreshSnapshot(
        renderSnapshot: VideoDetailDanmakuRenderSnapshot,
        playerViewModel: PlayerStateViewModel
    ) {
        updateSnapshot {
            $0.isEnabled = renderSnapshot.isDanmakuEnabled
            $0.settings = renderSnapshot.effectiveSettings
            $0.isPlaying = playerViewModel.isPlaying
            $0.playbackRate = playerViewModel.playbackRate.rawValue
            $0.hasPresentedPlayback = playerViewModel.isPlaybackSurfaceReady
            $0.isLoadShedding = Self.loadSheddingState(for: playerViewModel)
        }
    }

    private static func loadSheddingState(for playerViewModel: PlayerStateViewModel) -> Bool {
        playerViewModel.isUserSeeking
            || playerViewModel.isBuffering
            || playerViewModel.playbackRate.rawValue > 1.15
    }

    private func updateWindow(around playbackTime: TimeInterval, force: Bool) {
        let sanitizedTime = max(0, playbackTime)
        let centerBucket = Int(sanitizedTime / max(windowRecenterInterval, 1))
        guard force || lastWindowCenterBucket != centerBucket else { return }
        lastWindowCenterBucket = centerBucket

        let lowerTime = max(0, sanitizedTime - effectiveWindowLookBehind)
        let upperTime = sanitizedTime + effectiveWindowLookAhead
        let lowerIndex = firstItemIndex(atOrAfter: lowerTime)
        let upperIndex = firstItemIndex(after: upperTime)
        let nextRange = lowerIndex..<upperIndex
        let didChangeSource = publishedSourceItemsRevision != sourceItemsRevision
        guard force || didChangeSource || publishedWindowRange != nextRange else { return }

        publishedWindowRange = nextRange
        publishedSourceItemsRevision = sourceItemsRevision
        PlayerMetricsLog.signpostEvent(
            "VideoDetailDanmakuWindow",
            message: "count=\(nextRange.count) force=\(force) revision=\(sourceItemsRevision)"
        )
        if nextRange.isEmpty {
            updateSnapshot {
                $0.items = []
                $0.itemsRevision &+= 1
            }
        } else {
            updateSnapshot {
                $0.items = Array(allItems[nextRange])
                $0.itemsRevision &+= 1
            }
        }
    }

    private func updateSnapshot(_ transform: (inout VideoDetailDanmakuOverlaySnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        guard next != snapshot else { return }
        snapshot = next
    }

    private var effectiveWindowLookBehind: TimeInterval {
        snapshot.isLoadShedding ? 6 : normalWindowLookBehind
    }

    private var effectiveWindowLookAhead: TimeInterval {
        if snapshot.isLoadShedding {
            return 24
        }
        if snapshot.playbackRate > 1.15 || PlaybackEnvironment.current.isThermallyElevated {
            return 32
        }
        return normalWindowLookAhead
    }

    private func firstItemIndex(atOrAfter time: TimeInterval) -> Int {
        var lower = 0
        var upper = allItems.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if allItems[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func firstItemIndex(after time: TimeInterval) -> Int {
        var lower = 0
        var upper = allItems.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if allItems[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

private struct VideoDetailDanmakuOverlaySnapshot: Equatable {
    var items: [DanmakuItem] = []
    var itemsRevision = 0
    var isPlaying = false
    var playbackRate = 1.0
    var isEnabled = true
    var hasPresentedPlayback = false
    var isLoadShedding = false
    var settings: DanmakuSettings = .default

    static func == (lhs: VideoDetailDanmakuOverlaySnapshot, rhs: VideoDetailDanmakuOverlaySnapshot) -> Bool {
        lhs.itemsRevision == rhs.itemsRevision
            && lhs.isPlaying == rhs.isPlaying
            && lhs.playbackRate == rhs.playbackRate
            && lhs.isEnabled == rhs.isEnabled
            && lhs.hasPresentedPlayback == rhs.hasPresentedPlayback
            && lhs.isLoadShedding == rhs.isLoadShedding
            && lhs.settings == rhs.settings
    }
}

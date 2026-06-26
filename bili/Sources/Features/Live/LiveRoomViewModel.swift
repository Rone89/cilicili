import Combine
import Foundation

@MainActor
final class LiveRoomViewModel: ObservableObject {
    @Published private(set) var roomSummary: LiveRoomSummary?
    @Published private(set) var roomInfo: LiveRoomInfo?
    @Published private(set) var anchorInfo: LiveAnchorInfoData?
    @Published var playerViewModel: PlayerStateViewModel?
    @Published var state: LoadingState = .idle
    @Published var streamFallbackMessage: String?
    @Published var streamMenuItems: [LiveStreamMenuItem] = []
    @Published var qualityMenuItems: [LiveStreamQualityMenuItem] = []
    @Published var currentQualityTitle: String?
    @Published var isDanmakuEnabled: Bool
    @Published private(set) var danmakuSettings: DanmakuSettings
    @Published var isLiveDanmakuDiagnosticsEnabled = false
    @Published private(set) var isMutatingAnchorFollow = false
    @Published private(set) var interactionMessage: String?

    let seedRoom: LiveRoom
    let liveDanmakuRenderStore: LiveDanmakuRenderStore
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    var streamCandidates: [LiveStreamURLCandidate] = []
    var availableQualities: [LiveStreamQuality] = []
    var currentCandidateIndex = 0
    var selectedQualityQN: Int?
    private var loadingTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    var qualitySwitchTask: Task<Void, Never>?
    var startupWatchdogTask: Task<Void, Never>?
    var playbackStallWatchdogTask: Task<Void, Never>?
    var liveDanmakuService: LiveDanmakuService?
    var liveDanmakuStartupTask: Task<Void, Never>?
    var liveDanmakuClockTask: Task<Void, Never>?
    var liveDanmakuStartDate: Date?
    var liveDanmakuDiagnosticsDraft = LiveDanmakuDiagnosticSnapshot(roomID: 0)
    private var cancellables = Set<AnyCancellable>()
    private var loadGeneration = 0

    init(seedRoom: LiveRoom, api: BiliAPIClient, libraryStore: LibraryStore) {
        self.seedRoom = seedRoom
        self.api = api
        self.libraryStore = libraryStore
        self.isDanmakuEnabled = libraryStore.danmakuEnabled
        self.danmakuSettings = libraryStore.danmakuSettings
        let initialDiagnostics = LiveDanmakuDiagnosticSnapshot(roomID: seedRoom.roomID)
        self.liveDanmakuDiagnosticsDraft = initialDiagnostics
        self.liveDanmakuRenderStore = LiveDanmakuRenderStore(
            isEnabled: libraryStore.danmakuEnabled,
            settings: libraryStore.danmakuSettings,
            diagnostics: initialDiagnostics
        )
        self.liveDanmakuRenderStore.updateSettings(self.effectiveDanmakuSettings)
        libraryStore.$danmakuEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.applyGlobalDanmakuEnabled(isEnabled)
            }
            .store(in: &cancellables)
        libraryStore.$danmakuSettings
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self else { return }
                self.danmakuSettings = settings.normalized
                self.liveDanmakuRenderStore.updateSettings(self.effectiveDanmakuSettings)
            }
            .store(in: &cancellables)
    }

    deinit {
        loadingTask?.cancel()
        metadataTask?.cancel()
        qualitySwitchTask?.cancel()
        startupWatchdogTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        liveDanmakuStartupTask?.cancel()
        liveDanmakuClockTask?.cancel()
        liveDanmakuService?.stop()
    }

    var currentStreamTitle: String? {
        guard streamCandidates.indices.contains(currentCandidateIndex) else { return nil }
        return Self.streamTitle(for: streamCandidates[currentCandidateIndex], index: currentCandidateIndex)
    }

    var currentLoadGeneration: Int {
        loadGeneration
    }

    func startLoading() {
        guard playerViewModel == nil else { return }
        guard loadingTask == nil else { return }
        let generation = nextLoadGeneration()
        loadingTask = Task { [weak self] in
            await self?.loadFromNetwork(generation: generation)
        }
    }

    func reload() {
        stopCurrentLoadAndPlayback()
        streamCandidates = []
        availableQualities = []
        currentCandidateIndex = 0
        selectedQualityQN = nil
        updateStreamMenuItems()
        updateQualityMenuItems()
        streamFallbackMessage = nil
        state = .idle
        startLoading()
    }

    func stopPlaybackForNavigation() {
        stopCurrentLoadAndPlayback()
        streamCandidates = []
        availableQualities = []
        currentCandidateIndex = 0
        selectedQualityQN = nil
        updateStreamMenuItems()
        updateQualityMenuItems()
        streamFallbackMessage = nil
        if state.isLoading {
            state = .idle
        }
    }

    private func stopCurrentLoadAndPlayback() {
        loadGeneration += 1
        loadingTask?.cancel()
        metadataTask?.cancel()
        qualitySwitchTask?.cancel()
        startupWatchdogTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        liveDanmakuStartupTask?.cancel()
        loadingTask = nil
        metadataTask = nil
        qualitySwitchTask = nil
        startupWatchdogTask = nil
        playbackStallWatchdogTask = nil
        liveDanmakuStartupTask = nil
        playerViewModel?.onPlaybackFailure = nil
        playerViewModel?.stop()
        playerViewModel = nil
        stopLiveDanmaku(clearItems: true)
    }

    private func nextLoadGeneration() -> Int {
        loadGeneration += 1
        return loadGeneration
    }

    func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration
    }

    private func loadFromNetwork(generation: Int) async {
        guard isCurrentLoad(generation), playerViewModel == nil else {
            loadingTask = nil
            return
        }
        state = .loading
        defer {
            if isCurrentLoad(generation) {
                loadingTask = nil
            }
        }
        let api = self.api
        let roomID: Int
        if seedRoom.roomID > 0 {
            roomID = seedRoom.roomID
        } else if let uid = seedRoom.uid, uid > 0 {
            do {
                let summary = try await api.fetchLiveRoomSummary(uid: uid)
                guard !Task.isCancelled, isCurrentLoad(generation) else { return }
                roomSummary = summary
                roomID = summary.roomID
            } catch {
                guard !Task.isCancelled, isCurrentLoad(generation) else { return }
                state = .failed("没有找到这个 UP 的直播间")
                return
            }
        } else {
            state = .failed("这条直播动态缺少直播间信息")
            return
        }

        let resolvedRoomID = roomID
        metadataTask = Task { [weak self] in
            await self?.loadRoomMetadata(roomID: resolvedRoomID, generation: generation)
        }

        do {
            let streamResult = try await api.fetchLiveStreamInfo(roomID: resolvedRoomID, quality: selectedQualityQN)
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            let candidates = streamResult.candidates
            guard let firstCandidate = candidates.first else {
                state = .failed("没有获取到可播放的直播流")
                return
            }
            streamCandidates = candidates
            availableQualities = streamResult.playableQualities
            currentCandidateIndex = Self.preferredCandidateIndex(
                in: candidates,
                preferredQuality: selectedQualityQN,
                preferredSource: nil
            )
            selectedQualityQN = candidates[currentCandidateIndex].currentQN ?? selectedQualityQN
            updateStreamMenuItems()
            updateQualityMenuItems()
            let selectedCandidate = streamCandidates.indices.contains(currentCandidateIndex)
                ? streamCandidates[currentCandidateIndex]
                : firstCandidate
            installPlayer(for: selectedCandidate, generation: generation)
            if let playerViewModel {
                scheduleLiveDanmakuStart(roomID: resolvedRoomID, playerViewModel: playerViewModel, generation: generation)
            }
            state = .loaded
        } catch {
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            if roomInfo?.isLive == false || seedRoom.isLive == false {
                state = .failed("这个直播间当前未开播")
            } else {
                state = .failed("没有获取到可播放的直播流：\(error.localizedDescription)")
            }
        }
    }

    func toggleFollowAnchor() async {
        guard !isMutatingAnchorFollow else { return }
        guard let uid = anchorUIDForFollow else {
            interactionMessage = "没有找到主播 UID，无法关注"
            return
        }

        isMutatingAnchorFollow = true
        interactionMessage = nil
        let targetState = !isFollowingAnchor
        do {
            try await api.setUploaderFollowing(mid: uid, following: targetState)
            let roomID = self.roomID
            if roomID > 0 {
                anchorInfo = try? await api.fetchLiveAnchorInfo(roomID: roomID)
            }
            interactionMessage = targetState ? "已关注主播" : "已取消关注"
        } catch {
            interactionMessage = "关注操作失败：\(error.localizedDescription)"
        }
        isMutatingAnchorFollow = false
    }

    private func loadRoomMetadata(roomID: Int, generation: Int) async {
        let api = self.api
        async let roomInfoTask: LiveRoomInfo? = optionalFetch { try await api.fetchLiveRoomInfo(roomID: roomID) }
        async let anchorInfoTask: LiveAnchorInfoData? = optionalFetch { try await api.fetchLiveAnchorInfo(roomID: roomID) }

        let loadedRoomInfo = await roomInfoTask
        let loadedAnchorInfo = await anchorInfoTask
        guard !Task.isCancelled, isCurrentLoad(generation) else { return }
        roomInfo = loadedRoomInfo
        anchorInfo = loadedAnchorInfo
    }

    private func optionalFetch<T>(_ operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }

}

import Foundation
import Combine
import OSLog
import QuartzCore
import UIKit

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published var detail: VideoItem {
        didSet {
            refreshDetailDisplayMetrics()
            scheduleRenderStoreSync([.description, .playback, .networkDiagnostics, .danmaku])
        }
    }
    @Published var playVariants: [PlayVariant] = [] { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var selectedPlayVariant: PlayVariant? {
        didSet {
            scheduleRenderStoreSync([.playback, .networkDiagnostics])
        }
    }
    let renderStores = VideoDetailViewModelRenderStores()
    var detailPresentationState = VideoDetailPresentationState()
    var relatedStateStorage = VideoDetailRelatedState()
    var commentListState = VideoDetailCommentListState()
    @Published var selectedCID: Int? { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var state: LoadingState = .idle {
        didSet { scheduleRenderStoreSync(.playback) }
    }
    @Published var playURLState: LoadingState = .idle {
        didSet {
            scheduleRenderStoreSync(.playback)
            if playURLState.isLoading {
                beginPlaybackStartupAttempt()
            } else if case .failed = playURLState {
                finishPlaybackStartupWaiters(with: .failed)
            }
        }
    }
    @Published var isSupplementingPlayQualities = false { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var isSwitchingPlayQuality = false { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var pendingPlayVariantID: String? { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var interactionState = VideoInteractionState() {
        didSet {
            scheduleRenderStoreSync([.interaction, .description])
        }
    }
    @Published var interactionMessage: String? {
        didSet { scheduleRenderStoreSync(.interaction) }
    }
    @Published var isMutatingInteraction = false {
        didSet {
            scheduleRenderStoreSync([.interaction, .favoriteFolder, .description])
        }
    }
    var interactionMutationState = VideoDetailInteractionMutationState()
    @Published var favoriteFolders: [FavoriteFolder] = [] {
        didSet { scheduleRenderStoreSync(.favoriteFolder) }
    }
    @Published var favoriteFolderState: LoadingState = .idle {
        didSet { scheduleRenderStoreSync(.favoriteFolder) }
    }
    @Published var stablePlayerViewModel: PlayerStateViewModel? {
        didSet {
            cleanupStablePlaybackBeforeDeinit = Self.makeDeinitPlaybackCleanup(for: stablePlayerViewModel)
            scheduleRenderStoreSync([.networkDiagnostics, .playerIdentity])
        }
    }
    @Published var playbackFallbackMessage: String? {
        didSet {
            scheduleRenderStoreSync([.interaction, .networkDiagnostics])
        }
    }
    @Published var danmakuItems: [DanmakuItem] = []
    @Published var danmakuItemsRevision = 0
    @Published var danmakuState: LoadingState = .idle
    @Published var isDanmakuEnabled = true {
        didSet {
            scheduleRenderStoreSync([.playback, .danmakuSettings, .danmaku])
        }
    }
    @Published var danmakuSettings: DanmakuSettings = .default {
        didSet { scheduleRenderStoreSync([.danmakuSettings, .danmaku]) }
    }
    @Published var detailLoadElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published var playURLElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published var relatedElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published var lastPlayURLSource: String? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published var resumeDiagnostics: PlaybackResumeDiagnostics = .none {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    var commentThreadState = VideoDetailCommentThreadState()

    let serviceDependencies: VideoDetailViewModelDependencies
    var coreTaskState = VideoDetailCoreTaskState()
    var relatedTaskState = VideoDetailRelatedTaskState()
    var playbackWarmupTaskState = VideoDetailPlaybackWarmupTaskState()
    var lifecycleSubscriptionState = VideoDetailLifecycleSubscriptionState()
    var sponsorBlockState = VideoDetailSponsorBlockState()
    var danmakuLoadingState = VideoDetailDanmakuLoadingState()
    var stablePlayerState = VideoDetailStablePlayerState()
    var playbackTransitionState = VideoDetailPlaybackTransitionState()
    var playbackStartupWaitState = VideoDetailPlaybackStartupWaitState()
    var playbackRecoveryState = VideoDetailPlaybackRecoveryState()
    var renderStoreSyncState = VideoDetailRenderStoreSyncState()
    var navigationState = VideoDetailPlaybackNavigationState()
    var playVariantSwitchToken: UUID?
    var uploaderInteractionLoadState = VideoDetailUploaderInteractionLoadState()
    var lastUserSeekAt: Date?
    var loadTiming = VideoDetailViewModelLoadTimingState()
    private var cleanupStablePlaybackBeforeDeinit: (() -> Void)?
    let relatedLoadTimeoutNanoseconds: UInt64 = 5_000_000_000

    init(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sponsorBlockService: SponsorBlockService
    ) {
        self.detail = seedVideo
        self.selectedCID = seedVideo.cid ?? seedVideo.pages?.first?.cid
        self.serviceDependencies = VideoDetailViewModelDependencies(
            api: api,
            libraryStore: libraryStore,
            sponsorBlockService: sponsorBlockService
        )
        self.isDanmakuEnabled = libraryStore.danmakuEnabled
        self.danmakuSettings = libraryStore.danmakuSettings
        refreshDetailDisplayMetrics()
        refreshUploaderFanCountText()
        configureLifecycleBindings()
        syncAllRenderStores()
    }

    deinit {
        cleanupStablePlaybackBeforeDeinit?()
        Self.stopPlaybackBeforeDeinit(
            playbackTransitionState: &playbackTransitionState,
            navigationState: &navigationState
        )
        Self.tearDownBeforeDeinit(
            coreTaskState: &coreTaskState,
            playbackWarmupTaskState: &playbackWarmupTaskState,
            playbackRecoveryState: &playbackRecoveryState,
            playbackTransitionState: &playbackTransitionState,
            renderStoreSyncState: &renderStoreSyncState,
            playbackStartupWaitState: &playbackStartupWaitState,
            relatedTaskState: &relatedTaskState,
            uploaderInteractionLoadState: &uploaderInteractionLoadState,
            sponsorBlockState: &sponsorBlockState,
            danmakuLoadingState: &danmakuLoadingState
        )
        Self.cancelMediaWarmupsPreservingCache()
    }

}

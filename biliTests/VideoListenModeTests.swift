import AVFoundation
import XCTest
@testable import bili

final class VideoListenModeTests: XCTestCase {
    @MainActor
    func testAudioVariantsIncludeLosslessDolbyAndAACInDisplayOrder() throws {
        let data = try audioPlayURLData()

        let variants = data.videoListenAudioVariants(cdnPreference: .automatic)

        XCTAssertEqual(variants.map(\.kind), [.lossless, .dolby, .aac])
        XCTAssertEqual(variants.map(\.title), ["FLAC", "杜比音频", "AAC"])
        XCTAssertTrue(variants[0].subtitle.contains("1.41 Mbps"))
        XCTAssertTrue(variants[1].subtitle.contains("ec-3"))
        XCTAssertTrue(variants[2].subtitle.contains("192 kbps"))
    }

    @MainActor
    func testAutomaticAudioPrefersCompatibleAAC() throws {
        let data = try audioPlayURLData()

        XCTAssertEqual(data.dash?.bestAudioStream?.codecs, "mp4a.40.2")
    }

    @MainActor
    func testAudioFallbackUsesAutomaticThenRemainingCompatibleTrack() throws {
        let variants = try audioPlayURLData().videoListenAudioVariants(cdnPreference: .automatic)
        let automatic = try XCTUnwrap(variants.first(where: { $0.kind == .aac }))
        let lossless = try XCTUnwrap(variants.first(where: { $0.kind == .lossless }))

        XCTAssertEqual(
            VideoListenAudioFallbackResolver.fallback(
                automatic: automatic,
                variants: variants,
                failedIDs: [lossless.id]
            )?.id,
            automatic.id
        )
        XCTAssertEqual(
            VideoListenAudioFallbackResolver.fallback(
                automatic: automatic,
                variants: variants,
                failedIDs: [automatic.id]
            )?.kind,
            .lossless
        )
        XCTAssertNil(
            VideoListenAudioFallbackResolver.fallback(
                automatic: automatic,
                variants: variants,
                failedIDs: Set(variants.map(\.id))
            )
        )
    }

    @MainActor
    func testUGCSequenceResolverFindsPreviousAndNextPage() {
        let pages = [
            VideoPage(cid: 11, page: 1, part: "P1", duration: 10, dimension: nil),
            VideoPage(cid: 22, page: 2, part: "P2", duration: 20, dimension: nil),
            VideoPage(cid: 33, page: 3, part: "P3", duration: 30, dimension: nil),
        ]

        XCTAssertEqual(
            VideoListenSequenceResolver.page(in: pages, selectedCID: 22, direction: .previous)?.cid,
            11
        )
        XCTAssertEqual(
            VideoListenSequenceResolver.page(in: pages, selectedCID: 22, direction: .next)?.cid,
            33
        )
        XCTAssertNil(VideoListenSequenceResolver.page(in: pages, selectedCID: 11, direction: .previous))
        XCTAssertNil(VideoListenSequenceResolver.page(in: pages, selectedCID: 33, direction: .next))
    }

    @MainActor
    func testPGCSequenceResolverFindsAdjacentEpisode() throws {
        let season = try pgcSeasonInfo()
        let current = try XCTUnwrap(season.allPlayableEpisodes[1].videoItem(in: season))

        XCTAssertEqual(
            VideoListenSequenceResolver.episode(in: season, current: current, direction: .previous)?.pgcEpisodeID,
            101
        )
        XCTAssertEqual(
            VideoListenSequenceResolver.episode(in: season, current: current, direction: .next)?.pgcEpisodeID,
            103
        )
    }

    @MainActor
    func testPlaybackOrderPersists() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        store.setVideoListenPlaybackOrder(.repeatCurrent)

        XCTAssertEqual(store.videoListenPlaybackOrder, .repeatCurrent)
        XCTAssertEqual(
            LibraryStore(userDefaults: defaults).videoListenPlaybackOrder,
            .repeatCurrent
        )
    }

    @MainActor
    func testOfficialListenerSortOrderPersists() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertEqual(store.videoListenPlaylistSortOrder, .normal)

        store.setVideoListenPlaylistSortOrder(.reverse)

        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertEqual(restored.videoListenPlaylistSortOrder, .reverse)
    }

    @MainActor
    func testOfficialListenerRequestEncodingMatchesPlaylistContract() throws {
        let request = try BiliListenerPlaylistCodec.encodeRequest(
            aid: 1,
            cid: 2,
            cursor: nil,
            sortOrder: .reverse
        )

        XCTAssertEqual(
            request.hexString,
            "080510011a060801180120022a09085018d01f200228013a02080242020814"
        )
    }

    @MainActor
    func testOfficialListenerPagingRequestOmitsInitialAnchor() throws {
        let request = try BiliListenerPlaylistCodec.encodeRequest(
            aid: 1,
            cid: nil,
            cursor: "next",
            sortOrder: .random
        )

        XCTAssertEqual(
            request.hexString,
            "10012a09085018d01f200228013a0208034208081412046e657874"
        )
    }

    @MainActor
    func testOfficialListenerResponseDecodesVideoAndPagination() throws {
        let response = try XCTUnwrap(Data(hexString: "08031000180022430a06080118012002121b080112034f6e651a03706963220464657363283c407b4a034256311a0c080110021a025031203c2801220c0809120255501a046661636540013a0c0a046e657874120470726576"))

        let page = try BiliListenerPlaylistCodec.decodeResponse(response)

        XCTAssertEqual(page.totalCount, 3)
        XCTAssertFalse(page.reachedStart)
        XCTAssertFalse(page.reachedEnd)
        XCTAssertEqual(page.previousToken, "prev")
        XCTAssertEqual(page.nextToken, "next")
        XCTAssertEqual(page.videos.count, 1)
        XCTAssertEqual(page.videos[0].aid, 1)
        XCTAssertEqual(page.videos[0].bvid, "BV1")
        XCTAssertEqual(page.videos[0].title, "One")
        XCTAssertEqual(page.videos[0].owner?.mid, 9)
        XCTAssertEqual(page.videos[0].owner?.name, "UP")
        XCTAssertEqual(page.videos[0].pages?.first?.cid, 2)
        XCTAssertEqual(page.videos[0].pages?.first?.part, "P1")
    }

    @MainActor
    func testOfficialListenerGRPCFramesSupportIdentityAndGZIP() throws {
        let message = Data([0xAA, 0xBB])
        XCTAssertEqual(
            try BiliListenerPlaylistCodec.unframe(BiliListenerPlaylistCodec.frame(message)),
            message
        )

        let compressedFrame = try XCTUnwrap(Data(hexString: "01000000171f8b08000000000000034b4c4a0600c241243503000000"))
        XCTAssertEqual(
            try BiliListenerPlaylistCodec.unframe(compressedFrame),
            Data("abc".utf8)
        )
    }

    @MainActor
    func testOfficialListenerRequestRejectsMissingInitialCID() {
        XCTAssertThrowsError(
            try BiliListenerPlaylistCodec.encodeRequest(
                aid: 1,
                cid: nil,
                cursor: nil,
                sortOrder: .normal
            )
        ) { error in
            XCTAssertEqual(error as? BiliListenerPlaylistError, .invalidAnchor)
        }
    }

    @MainActor
    func testPlaybackEndResolverCoversEveryOrder() {
        XCTAssertEqual(
            VideoListenPlaybackEndResolver.action(
                playbackOrder: .sequential,
                sleepTimerOption: .off
            ),
            .advance
        )
        XCTAssertEqual(
            VideoListenPlaybackEndResolver.action(
                playbackOrder: .repeatCurrent,
                sleepTimerOption: .off
            ),
            .replayCurrent
        )
        XCTAssertEqual(
            VideoListenPlaybackEndResolver.action(
                playbackOrder: .stopAfterCurrent,
                sleepTimerOption: .off
            ),
            .pause
        )
    }

    @MainActor
    func testEndOfCurrentSleepTimerOverridesPlaybackOrder() {
        for order in VideoListenPlaybackOrder.allCases {
            XCTAssertEqual(
                VideoListenPlaybackEndResolver.action(
                    playbackOrder: order,
                    sleepTimerOption: .endOfCurrent
                ),
                .pause
            )
        }
    }

    @MainActor
    func testSleepTimerCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            VideoListenSleepTimerCountdownFormatter.text(
                deadline: now.addingTimeInterval(65),
                now: now
            ),
            "01:05"
        )
        XCTAssertEqual(
            VideoListenSleepTimerCountdownFormatter.text(
                deadline: now.addingTimeInterval(3_661),
                now: now
            ),
            "1:01:01"
        )
        XCTAssertEqual(
            VideoListenSleepTimerCountdownFormatter.text(
                deadline: now.addingTimeInterval(-1),
                now: now
            ),
            "00:00"
        )
    }

    @MainActor
    func testAudioInterruptionStateHonorsExplicitPause() {
        var state = VideoListenAudioInterruptionState()

        XCTAssertTrue(state.begin(hadPlaybackIntent: true))
        state.cancelAutomaticResume()
        XCTAssertFalse(state.end(systemAllowsResume: true))

        XCTAssertTrue(state.begin(hadPlaybackIntent: true))
        XCTAssertFalse(state.end(systemAllowsResume: false))

        XCTAssertTrue(state.begin(hadPlaybackIntent: true))
        XCTAssertTrue(state.end(systemAllowsResume: true))
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.shouldResume)
    }

    @MainActor
    func testUGCQueueBuilderMarksCurrentPage() {
        let pages = [
            VideoPage(cid: 11, page: 1, part: "开场", duration: 65, dimension: nil),
            VideoPage(cid: 22, page: 2, part: "正片", duration: 3_661, dimension: nil),
        ]

        let entries = VideoListenQueueBuilder.pages(pages, selectedCID: 22)

        XCTAssertEqual(entries.map(\.title), ["开场", "正片"])
        XCTAssertEqual(entries.map(\.subtitle), ["1:05", "1:01:01"])
        XCTAssertEqual(entries.map(\.isCurrent), [false, true])
    }

    @MainActor
    func testPGCQueueBuilderMarksCurrentEpisode() throws {
        let season = try pgcSeasonInfo()
        let current = try XCTUnwrap(season.allPlayableEpisodes[1].videoItem(in: season))

        let entries = VideoListenQueueBuilder.episodes(in: season, current: current)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.firstIndex(where: \.isCurrent), 1)
        XCTAssertEqual(entries[1].title, "2")
    }

    @MainActor
    func testUploaderQueueKeepsSinglePartCurrentVideoAtSourcePosition() {
        let previous = makeVideo(bvid: "BV-previous", aid: 101, title: "上一条", pages: [])
        let current = makeVideo(bvid: "BV-current", aid: 102, title: "当前视频", pages: [])
        let next = makeVideo(bvid: "BV-next", aid: 103, title: "下一条", pages: [])
        var session = VideoListenQueueSession(seedVideo: current)
        let generation = session.beginInitialLoad(source: .uploader(mid: 42), anchor: current)

        XCTAssertTrue(
            session.finishInitialLoad(
                videos: [previous, current, next],
                anchor: current,
                source: .uploader(mid: 42),
                nextPage: 1,
                nextCursor: nil,
                hasMore: false,
                generation: generation
            )
        )

        let entries = VideoListenQueueBuilder.entries(
            videos: session.videos,
            current: current,
            selectedCID: current.cid
        )
        XCTAssertEqual(entries.map(\.title), ["上一条", "当前视频", "下一条"])
        XCTAssertEqual(entries.firstIndex(where: \.isCurrent), 1)
    }

    @MainActor
    func testUploaderQueueExpandsOnlyCurrentMultiPartVideo() {
        let pages = [
            VideoPage(cid: 21, page: 1, part: "上集", duration: 10, dimension: nil),
            VideoPage(cid: 22, page: 2, part: "下集", duration: 20, dimension: nil),
        ]
        let previous = makeVideo(bvid: "BV-previous", aid: 201, title: "上一条", pages: [])
        let current = makeVideo(bvid: "BV-current", aid: 202, title: "当前合集", pages: pages)
        let next = makeVideo(bvid: "BV-next", aid: 203, title: "下一条", pages: [])

        let entries = VideoListenQueueBuilder.entries(
            videos: [previous, current, next],
            current: current,
            selectedCID: 22
        )

        XCTAssertEqual(entries.map(\.title), ["上一条", "上集", "下集", "下一条"])
        XCTAssertEqual(entries.map(\.isCurrent), [false, false, true, false])
    }

    @MainActor
    func testUploaderQueueDeduplicatesPartialAndFullVideoByAID() {
        let partial = makeVideo(bvid: "", aid: 302, title: "列表简版", pages: [])
        let current = makeVideo(bvid: "BV-current", aid: 302, title: "详情完整版", pages: [])
        let next = makeVideo(bvid: "BV-next", aid: 303, title: "下一条", pages: [])
        var session = VideoListenQueueSession(seedVideo: current)
        let generation = session.beginInitialLoad(source: .uploader(mid: 42), anchor: current)

        XCTAssertTrue(
            session.finishInitialLoad(
                videos: [partial, current, next, next],
                anchor: current,
                source: .uploader(mid: 42),
                nextPage: 1,
                nextCursor: nil,
                hasMore: false,
                generation: generation
            )
        )

        XCTAssertEqual(session.videos.count, 2)
        XCTAssertEqual(session.videos.first?.title, "详情完整版")
        XCTAssertEqual(session.videos.last?.title, "下一条")
    }

    @MainActor
    func testUploaderQueueResolvesPreviousAndNextVideo() {
        let previous = makeVideo(bvid: "BV-previous", aid: 401, title: "上一条", pages: [])
        let current = makeVideo(bvid: "BV-current", aid: 402, title: "当前视频", pages: [])
        let next = makeVideo(bvid: "BV-next", aid: 403, title: "下一条", pages: [])
        var session = VideoListenQueueSession(seedVideo: current)
        let generation = session.beginInitialLoad(source: .uploader(mid: 42), anchor: current)
        XCTAssertTrue(
            session.finishInitialLoad(
                videos: [previous, current, next],
                anchor: current,
                source: .uploader(mid: 42),
                nextPage: 1,
                nextCursor: nil,
                hasMore: false,
                generation: generation
            )
        )

        XCTAssertEqual(session.video(relativeTo: current, direction: .previous)?.aid, 401)
        XCTAssertEqual(session.video(relativeTo: current, direction: .next)?.aid, 403)
        XCTAssertNil(session.video(relativeTo: previous, direction: .previous))
        XCTAssertNil(session.video(relativeTo: next, direction: .next))
    }

    @MainActor
    func testOfficialListenerQueuePrependsAndAppendsPaginationWithoutLosingTokens() throws {
        let oldest = makeVideo(bvid: "BV-oldest", aid: 600, title: "更早", pages: [])
        let previous = makeVideo(bvid: "BV-previous", aid: 601, title: "上一条", pages: [])
        let current = makeVideo(bvid: "BV-current", aid: 602, title: "当前视频", pages: [])
        let next = makeVideo(bvid: "BV-next", aid: 603, title: "下一条", pages: [])
        let newest = makeVideo(bvid: "BV-newest", aid: 604, title: "更晚", pages: [])
        var session = VideoListenQueueSession(seedVideo: current)
        let generation = session.beginInitialLoad(
            source: .officialListener(anchorAID: 602, sortOrder: .normal),
            anchor: current
        )

        XCTAssertTrue(
            session.finishInitialLoad(
                videos: [previous, current, next],
                anchor: current,
                source: .officialListener(anchorAID: 602, sortOrder: .normal),
                nextPage: 1,
                nextCursor: nil,
                hasMore: false,
                listenerPreviousToken: "prev-1",
                listenerNextToken: "next-1",
                generation: generation
            )
        )

        let previousGeneration = try XCTUnwrap(session.beginLoadMore())
        XCTAssertTrue(
            session.finishLoadMore(
                videos: [oldest, previous],
                nextPage: 2,
                nextCursor: nil,
                hasMore: false,
                listenerDirection: .previous,
                listenerPreviousToken: nil,
                listenerNextToken: "ignored",
                generation: previousGeneration
            )
        )
        XCTAssertEqual(session.videos.map(\.aid), [600, 601, 602, 603])
        XCTAssertNil(session.listenerPreviousToken)
        XCTAssertEqual(session.listenerNextToken, "next-1")

        let nextGeneration = try XCTUnwrap(session.beginLoadMore())
        XCTAssertTrue(
            session.finishLoadMore(
                videos: [next, newest],
                nextPage: 3,
                nextCursor: nil,
                hasMore: false,
                listenerDirection: .next,
                listenerPreviousToken: "ignored",
                listenerNextToken: nil,
                generation: nextGeneration
            )
        )
        XCTAssertEqual(session.videos.map(\.aid), [600, 601, 602, 603, 604])
        XCTAssertFalse(session.hasMore)
        XCTAssertNil(session.listenerNextToken)
    }

    @MainActor
    func testQueueCancellationClearsLoadingStateAndAllowsPaginationRetry() throws {
        let current = makeVideo(bvid: "BV-current", aid: 501, title: "当前视频", pages: [])
        let next = makeVideo(bvid: "BV-next", aid: 502, title: "下一条", pages: [])
        var session = VideoListenQueueSession(seedVideo: current)
        let initialGeneration = session.beginInitialLoad(source: .uploader(mid: 42), anchor: current)

        session.cancelLoading(generation: initialGeneration)

        XCTAssertFalse(session.isLoadingInitial)
        XCTAssertFalse(session.isLoadingMore)

        let retryGeneration = session.beginInitialLoad(source: .uploader(mid: 42), anchor: current)
        XCTAssertTrue(
            session.finishInitialLoad(
                videos: [current, next],
                anchor: current,
                source: .uploader(mid: 42),
                nextPage: 1,
                nextCursor: nil,
                hasMore: true,
                generation: retryGeneration
            )
        )
        let loadMoreGeneration = try XCTUnwrap(session.beginLoadMore())

        session.cancelLoading(generation: loadMoreGeneration)

        XCTAssertFalse(session.isLoadingMore)
        XCTAssertTrue(session.hasMore)
        XCTAssertNotNil(session.beginLoadMore())
    }

    @MainActor
    func testDuplicateQueueSchedulingKeepsExistingTaskAlive() throws {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        let viewModel = makeViewModel(pages: [], libraryStore: libraryStore)
        viewModel.playbackContentMode = .audioOnly

        viewModel.scheduleVideoListenQueuePreparation()
        let firstTask = try XCTUnwrap(viewModel.videoListenQueueTask)
        viewModel.scheduleVideoListenQueuePreparation()

        XCTAssertFalse(firstTask.isCancelled)
        XCTAssertEqual(viewModel.videoListenQueueTaskGeneration, 1)
        viewModel.cancelVideoListenQueueTasks(resetSession: false)
    }

    @MainActor
    func testPlaybackEndedCallbackOnlyFiresOnceForRepeatedEndedState() async {
        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: URL(string: "https://example.com/audio.m4s"),
            title: "听视频结束回调",
            referer: "https://www.bilibili.com",
            playbackContentMode: .audioOnly,
            engine: engine
        )
        defer { player.stop() }
        var endedCount = 0
        player.onPlaybackEnded = { endedCount += 1 }

        engine.onPlaybackStateChange?(.ended)
        engine.onPlaybackStateChange?(.ended)
        await Task.yield()

        XCTAssertEqual(endedCount, 1)
    }

    @MainActor
    func testTrackNavigationCallbacksRespectAvailability() {
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: URL(string: "https://example.com/audio.m4s"),
            title: "听视频上下集",
            referer: "https://www.bilibili.com",
            playbackContentMode: .audioOnly,
            engine: PlayerLifecycleEngineSpy(isPlaying: true)
        )
        defer { player.stop() }
        var previousCount = 0
        var nextCount = 0
        player.onPreviousTrackRequested = { previousCount += 1 }
        player.onNextTrackRequested = { nextCount += 1 }

        player.requestPreviousTrack()
        player.requestNextTrack()
        XCTAssertEqual(previousCount, 0)
        XCTAssertEqual(nextCount, 0)

        player.setTrackNavigationAvailability(hasPrevious: true, hasNext: true)
        player.requestPreviousTrack()
        player.requestNextTrack()
        XCTAssertEqual(previousCount, 1)
        XCTAssertEqual(nextCount, 1)
    }

    @MainActor
    func testPendingAutomaticAdvancePreservesAudioModeAndAutoplayIntent() {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        libraryStore.setVideoDetailAutoplayEnabled(false)
        let sessionStore = SessionStore(
            keychain: KeychainStore(service: "cc.bili.tests.listen.\(UUID().uuidString)")
        )
        let api = BiliAPIClient(
            session: URLSession(configuration: .ephemeral),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
        let viewModel = VideoDetailViewModel(
            seedVideo: VideoItem(
                bvid: "BV-listen",
                aid: nil,
                title: "听视频",
                pic: nil,
                desc: nil,
                duration: 60,
                pubdate: nil,
                owner: nil,
                stat: nil,
                cid: 11,
                pages: nil,
                dimension: nil
            ),
            api: api,
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: SponsorBlockService(session: URLSession(configuration: .ephemeral))
        )
        viewModel.playbackContentMode = .audioOnly
        viewModel.pendingVideoListenPlaybackIntent = true

        viewModel.resetPlaybackStateForSelectedPage()

        XCTAssertEqual(viewModel.playbackContentMode, .audioOnly)
        XCTAssertTrue(viewModel.currentPlaybackIntent())
        viewModel.pendingVideoListenPlaybackIntent = false
        XCTAssertFalse(viewModel.currentPlaybackIntent())
    }

    @MainActor
    func testListenSessionDoesNotRestoreAcrossDetailInstances() throws {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        let sessionStore = VideoListenPlaybackSessionStore()
        let video = makeVideo(bvid: "BV-listen-restore", pages: [])
        let otherVideo = makeVideo(bvid: "BV-listen-other", pages: [])
        let audioData = try audioPlayURLData()
        let aacPreference = try XCTUnwrap(
            audioData.videoListenAudioVariants(cdnPreference: .automatic)
                .first(where: { $0.kind == .aac })
        ).preferenceKey
        sessionStore.save(
            VideoListenPlaybackSessionState(
                audioPreferenceKey: aacPreference,
                wantsPlayback: false
            ),
            for: video
        )

        let restoredViewModel = makeViewModel(
            video: video,
            libraryStore: libraryStore,
            playbackSessionStore: sessionStore
        )
        restoredViewModel.applyVideoListenAudioVariants(from: audioData)

        XCTAssertEqual(restoredViewModel.playbackContentMode, .video)
        XCTAssertNil(restoredViewModel.selectedVideoListenAudioPreferenceKey)

        let unrelatedViewModel = makeViewModel(
            video: otherVideo,
            libraryStore: libraryStore,
            playbackSessionStore: sessionStore
        )
        unrelatedViewModel.applyVideoListenAudioVariants(from: audioData)

        XCTAssertEqual(unrelatedViewModel.playbackContentMode, .video)
        XCTAssertNil(unrelatedViewModel.selectedVideoListenAudioPreferenceKey)
    }

    @MainActor
    func testNavigationStopClearsListenSessionForReopen() {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        let sessionStore = VideoListenPlaybackSessionStore()
        let video = makeVideo(bvid: "BV-listen-exit", pages: [])
        let viewModel = makeViewModel(
            video: video,
            libraryStore: libraryStore,
            playbackSessionStore: sessionStore
        )
        viewModel.playbackContentMode = .audioOnly
        viewModel.persistVideoListenPlaybackSession(wantsPlayback: true)
        XCTAssertNotNil(sessionStore.state(for: video))

        viewModel.stopPlaybackForNavigation()

        XCTAssertNil(sessionStore.state(for: video))
    }

    @MainActor
    func testRelatedVideoReturnResumesAutoplayWithoutExplicitPlaybackPrompt() async {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        libraryStore.setVideoDetailAutoplayEnabled(true)
        let viewModel = makeViewModel(
            video: makeVideo(bvid: "BV-related-return", pages: []),
            libraryStore: libraryStore,
            playbackSessionStore: VideoListenPlaybackSessionStore()
        )
        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: URL(string: "https://example.com/video.m4s"),
            audioURL: nil,
            title: "相关视频返回自动续播",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        defer { player.stop() }
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        player.setPlaybackIntent(true)
        viewModel.stablePlayerViewModel = player

        viewModel.markRelatedVideoNavigation()
        viewModel.stopPlaybackForNavigation()
        await viewModel.resumePlaybackAfterCoveredNavigationIfNeeded()

        XCTAssertFalse(viewModel.isAwaitingRelatedVideoReturnPlayback)
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.showsExplicitPlaybackStartControl)
    }

    @MainActor
    func testUserPauseDuringInterruptionCancelsAutomaticResume() async {
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: URL(string: "https://example.com/audio.m4s"),
            title: "听视频中断恢复",
            referer: "https://www.bilibili.com",
            playbackContentMode: .audioOnly,
            engine: engine
        )
        defer { player.stop() }
        player.play()
        XCTAssertTrue(player.wantsAutoplay)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
            ]
        )
        await settleNotificationDelivery()
        XCTAssertGreaterThanOrEqual(engine.pauseCallCount, 1)

        player.pause()
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
            ]
        )
        await settleNotificationDelivery()

        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertEqual(engine.playCallCount, 0)
    }

    @MainActor
    func testMediaServicesResetRepreparesDetachedAudioPlayback() async {
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: URL(string: "https://example.com/audio.m4s"),
            title: "听视频音频服务恢复",
            referer: "https://www.bilibili.com",
            playbackContentMode: .audioOnly,
            engine: engine
        )
        defer { player.stop() }
        player.play()

        NotificationCenter.default.post(
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        await settleNotificationDelivery(milliseconds: 100)

        XCTAssertEqual(engine.prepareCallCount, 1)
        XCTAssertTrue(player.wantsAutoplay)
    }

    @MainActor
    func testQueueSelectionPreservesPausedIntent() throws {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        let pages = [
            VideoPage(cid: 11, page: 1, part: "P1", duration: 10, dimension: nil),
            VideoPage(cid: 22, page: 2, part: "P2", duration: 20, dimension: nil),
        ]
        let viewModel = makeViewModel(pages: pages, libraryStore: libraryStore)
        viewModel.playbackContentMode = .audioOnly
        viewModel.pendingVideoListenPlaybackIntent = false
        let target = try XCTUnwrap(
            viewModel.videoListenQueueEntries.first { !$0.isCurrent }
        )

        viewModel.selectVideoListenQueueEntry(target)

        XCTAssertEqual(viewModel.selectedCID, 22)
        XCTAssertEqual(viewModel.playbackContentMode, .audioOnly)
        XCTAssertFalse(viewModel.currentPlaybackIntent())
    }

    @MainActor
    func testCancellingSleepTimerClearsStateAndCancelsTask() throws {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        let viewModel = makeViewModel(pages: [], libraryStore: libraryStore)
        viewModel.playbackContentMode = .audioOnly

        viewModel.setVideoListenSleepTimer(.minutes15)
        let task = try XCTUnwrap(viewModel.videoListenSleepTimerTask)
        XCTAssertNotNil(viewModel.videoListenSleepTimerDeadline)

        viewModel.cancelVideoListenSleepTimer()

        XCTAssertTrue(task.isCancelled)
        XCTAssertEqual(viewModel.videoListenSleepTimerOption, .off)
        XCTAssertNil(viewModel.videoListenSleepTimerDeadline)
        XCTAssertNil(viewModel.videoListenSleepTimerTask)
    }

    private func audioPlayURLData() throws -> PlayURLData {
        let json = """
        {
          "quality": 80,
          "dash": {
            "duration": 120,
            "video": [],
            "audio": [
              {
                "id": 30280,
                "baseUrl": "https://example.com/audio-aac.m4s",
                "bandwidth": 192000,
                "codecs": "mp4a.40.2",
                "mimeType": "audio/mp4"
              }
            ],
            "dolby": {
              "audio": [
                {
                  "id": 30250,
                  "baseUrl": "https://example.com/audio-dolby.m4s",
                  "bandwidth": 448000,
                  "codecs": "ec-3",
                  "mimeType": "audio/mp4"
                }
              ]
            },
            "flac": {
              "audio": {
                "id": 30251,
                "baseUrl": "https://example.com/audio-flac.m4s",
                "bandwidth": 1411200,
                "codecs": "flac",
                "mimeType": "audio/mp4"
              }
            }
          }
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func pgcSeasonInfo() throws -> PgcSeasonInfo {
        let json = """
        {
          "season_id": 42,
          "title": "测试番剧",
          "episodes": [
            {"id": 101, "ep_id": 101, "bvid": "BV101", "cid": 1001, "title": "1"},
            {"id": 102, "ep_id": 102, "bvid": "BV102", "cid": 1002, "title": "2"},
            {"id": 103, "ep_id": 103, "bvid": "BV103", "cid": 1003, "title": "3"}
          ]
        }
        """
        return try JSONDecoder().decode(PgcSeasonInfo.self, from: Data(json.utf8))
    }

    @MainActor
    private func makeViewModel(
        pages: [VideoPage],
        libraryStore: LibraryStore
    ) -> VideoDetailViewModel {
        makeViewModel(
            video: makeVideo(bvid: "BV-listen-queue", pages: pages),
            libraryStore: libraryStore,
            playbackSessionStore: VideoListenPlaybackSessionStore()
        )
    }

    @MainActor
    private func makeViewModel(
        video: VideoItem,
        libraryStore: LibraryStore,
        playbackSessionStore: VideoListenPlaybackSessionStore
    ) -> VideoDetailViewModel {
        let sessionStore = SessionStore(
            keychain: KeychainStore(service: "cc.bili.tests.listen.\(UUID().uuidString)")
        )
        let api = BiliAPIClient(
            session: URLSession(configuration: .ephemeral),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
        return VideoDetailViewModel(
            seedVideo: video,
            api: api,
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: SponsorBlockService(session: URLSession(configuration: .ephemeral)),
            videoListenPlaybackSessionStore: playbackSessionStore
        )
    }

    private func makeVideo(
        bvid: String,
        aid: Int? = nil,
        title: String = "听视频队列",
        pages: [VideoPage]
    ) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: nil,
            desc: nil,
            duration: pages.reduce(0) { $0 + ($1.duration ?? 0) },
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: pages.first?.cid,
            pages: pages,
            dimension: nil
        )
    }

    @MainActor
    private func settleNotificationDelivery(milliseconds: UInt64 = 50) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        await Task.yield()
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "cc.bili.tests.listen.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        self.init(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

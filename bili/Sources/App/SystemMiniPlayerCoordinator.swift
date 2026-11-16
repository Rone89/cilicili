import AVKit
import Foundation
import UIKit

/// Coordinates keeping a playing `PlayerStateViewModel` alive in system
/// Picture-in-Picture after the user exits `VideoDetailView`, and handing that
/// live session back seamlessly when the user restores or re-opens the video.
@MainActor
final class SystemMiniPlayerCoordinator {
    static let shared = SystemMiniPlayerCoordinator()

    struct RetainedSession {
        let video: VideoItem
        let selectedCID: Int?
        let playVariants: [PlayVariant]
        let selectedPlayVariant: PlayVariant?
        let currentPlayURLData: PlayURLData?
        let isDanmakuEnabled: Bool
        let hasResolvedDetailMetadata: Bool
        let stablePlayerIdentity: String?
        let playerViewModel: PlayerStateViewModel
        let recordsPlaybackHistory: Bool
        let api: BiliAPIClient
        let libraryStore: LibraryStore
        var isRestoringUserInterface = false
    }

    private let stagingHostView = SystemMiniPlayerStagingView()
    private(set) var activeSession: RetainedSession?

    var supportsPictureInPicture: () -> Bool = {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var onStartPictureInPicture: ((PlayerStateViewModel, @escaping @MainActor () -> Void) -> Void)?
    var onAttachStagingSurface: ((SystemMiniPlayerStagingView, PlayerStateViewModel, CGRect?, Bool) -> Void)?
    var onDetachStagingSurface: ((SystemMiniPlayerStagingView, PlayerStateViewModel?) -> Void)?

    private init() {}

    func hasRetainedSession(for targetVideo: VideoItem) -> Bool {
        guard let session = activeSession else { return false }
        return Self.matches(session: session, targetVideo: targetVideo)
    }

    func canStartMiniPlayer(for playerViewModel: PlayerStateViewModel?) -> Bool {
        guard let playerViewModel else { return false }
        guard supportsPictureInPicture() else { return false }
        return playerViewModel.isEligibleForExitPictureInPicture
    }

    @discardableResult
    func beginMiniPlayer(
        with session: RetainedSession,
        preferredFrameInWindow: CGRect? = nil,
        preferredWindow: UIWindow? = nil
    ) -> Bool {
        guard canStartMiniPlayer(for: session.playerViewModel) else { return false }
        stopActiveMiniPlayer()

        let player = session.playerViewModel
        activeSession = session

        let allowsAutoInline = session.libraryStore.pictureInPictureEnabled
        if let onAttachStagingSurface {
            onAttachStagingSurface(stagingHostView, player, preferredFrameInWindow, allowsAutoInline)
        } else {
            attachDefaultStagingSurface(
                for: player,
                preferredFrameInWindow: preferredFrameInWindow,
                preferredWindow: preferredWindow,
                allowsAutomaticInline: allowsAutoInline
            )
        }

        configureRetainedCallbacks(for: player)

        if let onStartPictureInPicture {
            onStartPictureInPicture(player) { [weak self, weak player] in
                guard let self, let player else { return }
                self.stopMiniPlayer(ifCurrentPlayer: player)
            }
        } else {
            player.startPictureInPictureForMiniPlayer { [weak self, weak player] in
                guard let self, let player else { return }
                self.stopMiniPlayer(ifCurrentPlayer: player)
            }
        }
        return true
    }

    /// Claims an active mini-player session if it matches `targetVideo`.
    /// If another video is currently playing in the mini-player, it is stopped so
    /// opening a different video never leaves overlapping audio or a stale PiP window.
    func claimSessionIfMatching(for targetVideo: VideoItem) -> RetainedSession? {
        guard let session = activeSession else { return nil }
        guard Self.matches(session: session, targetVideo: targetVideo) else {
            stopActiveMiniPlayer()
            return nil
        }

        activeSession = nil
        let player = session.playerViewModel
        player.onPictureInPictureDidStart = nil
        player.onPictureInPictureDidStop = nil
        player.onPictureInPictureFailedToStart = nil
        player.beginSurfaceMigrationHold()
        detachStagingContainer(for: player, waitsForAdoptedSurfaceAttachment: true)
        return session
    }

    func prepareForOpeningVideo(_ targetVideo: VideoItem) {
        guard let session = activeSession else { return }
        if !Self.matches(session: session, targetVideo: targetVideo) {
            stopActiveMiniPlayer()
        }
    }

    func stopActiveMiniPlayer() {
        guard let session = activeSession else {
            detachStagingContainer(for: nil)
            return
        }
        activeSession = nil
        let player = session.playerViewModel
        player.onPictureInPictureDidStart = nil
        player.onPictureInPictureDidStop = nil
        player.onPictureInPictureFailedToStart = nil
        player.restoreUserInterfaceForPictureInPictureStop = nil
        flushPlaybackHistoryIfNeeded(for: session)
        player.stopPictureInPictureIfNeeded()
        player.stop(reason: .navigation)
        detachStagingContainer(for: player)
    }

    private func stopMiniPlayer(ifCurrentPlayer player: PlayerStateViewModel) {
        guard let session = activeSession,
              session.playerViewModel === player
        else { return }
        stopActiveMiniPlayer()
    }

    private func configureRetainedCallbacks(for player: PlayerStateViewModel) {
        player.restoreUserInterfaceForPictureInPictureStop = { [weak self, weak player] in
            guard let self,
                  let player,
                  var session = self.activeSession,
                  session.playerViewModel === player
            else { return false }

            session.isRestoringUserInterface = true
            self.activeSession = session
            let didRestore = await PictureInPictureRestoreCoordinator.shared.restorePlaybackUI(for: session.video)
            if !didRestore {
                if var latest = self.activeSession, latest.playerViewModel === player {
                    latest.isRestoringUserInterface = false
                    self.activeSession = latest
                }
                self.stopMiniPlayer(ifCurrentPlayer: player)
            }
            return didRestore
        }

        player.onPictureInPictureDidStop = { [weak self, weak player] in
            guard let self, let player else { return }
            guard let session = self.activeSession,
                  session.playerViewModel === player,
                  !session.isRestoringUserInterface
            else { return }
            self.stopMiniPlayer(ifCurrentPlayer: player)
        }

        player.onPictureInPictureFailedToStart = { [weak self, weak player] in
            guard let self, let player else { return }
            self.stopMiniPlayer(ifCurrentPlayer: player)
        }
    }

    private func attachDefaultStagingSurface(
        for player: PlayerStateViewModel,
        preferredFrameInWindow: CGRect?,
        preferredWindow: UIWindow?,
        allowsAutomaticInline: Bool
    ) {
        if let targetWindow = preferredWindow ?? activeKeyWindow(),
           let hostParent = targetWindow.rootViewController?.view ?? targetWindow as UIView? {
            if stagingHostView.superview !== hostParent {
                stagingHostView.removeFromSuperview()
                hostParent.insertSubview(stagingHostView, at: 0)
            }
            let targetFrame: CGRect
            if let preferredFrameInWindow,
               preferredFrameInWindow.width > 16,
               preferredFrameInWindow.height > 16 {
                targetFrame = targetWindow.convert(preferredFrameInWindow, to: hostParent)
            } else {
                let width = max(hostParent.bounds.width, 320)
                let topInset = hostParent.safeAreaInsets.top
                targetFrame = CGRect(x: 0, y: topInset, width: width, height: width * 9.0 / 16.0)
            }
            UIView.performWithoutAnimation {
                stagingHostView.frame = targetFrame
                stagingHostView.alpha = 0.015
                stagingHostView.isHidden = false
                stagingHostView.layoutIfNeeded()
            }
        }

        player.beginSurfaceMigrationHold()
        player.setAutomaticPictureInPictureFromInlineAllowed(allowsAutomaticInline)
        player.setPictureInPictureEnabled(true)
        stagingHostView.surfaceView.configureBoundsRefresh(for: player, synchronously: true)
        stagingHostView.surfaceView.setPictureInPictureEnabled(true)
        stagingHostView.surfaceView.setShowsSystemPlaybackControls(false)
        stagingHostView.surfaceView.setPlayerViewModel(player, prefersNativePlaybackControls: false)
        player.attachSurface(
            stagingHostView.surfaceView,
            prefersNativePlaybackControls: false,
            preservesReadinessDuringSurfaceHandoff: true
        )
        player.endSurfaceMigrationHold()
        stagingHostView.surfaceView.setNeedsLayout()
        stagingHostView.surfaceView.invalidateVideoLayout()
        stagingHostView.layoutIfNeeded()
    }

    private func detachStagingContainer(
        for player: PlayerStateViewModel?,
        waitsForAdoptedSurfaceAttachment: Bool = false
    ) {
        if let onDetachStagingSurface {
            onDetachStagingSurface(stagingHostView, player)
            return
        }
        let staging = stagingHostView
        guard waitsForAdoptedSurfaceAttachment else {
            if let player, !player.isTerminated {
                player.detachSurface(staging.surfaceView, preservesReadinessDuringSurfaceHandoff: true)
            }
            staging.removeFromSuperview()
            return
        }
        // Let the adopting detail view mount its surface first so `AVPlayerLayer`
        // transfers straight into the detail view without ever leaving a live window.
        Task { @MainActor in
            for _ in 0..<25 {
                await Task.yield()
                guard self.activeSession == nil else { return }
                if staging.surfaceView.subviews.isEmpty,
                   staging.surfaceView.drawableView.layer.sublayers?.contains(where: { $0 is AVPlayerLayer }) != true {
                    break
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard self.activeSession == nil else { return }
            if let player,
               !player.isTerminated,
               staging.surfaceView.isBound(to: player) {
                player.detachSurface(staging.surfaceView, preservesReadinessDuringSurfaceHandoff: true)
            }
            staging.removeFromSuperview()
        }
    }

    private func flushPlaybackHistoryIfNeeded(for session: RetainedSession) {
        guard session.recordsPlaybackHistory else { return }
        VideoDetailViewModel.flushPlaybackHistoryProgress(
            video: session.video,
            cid: session.selectedCID ?? session.video.cid,
            resumeTime: session.playerViewModel.currentTime,
            libraryStore: session.libraryStore,
            api: session.api
        )
    }

    private func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
    }

    static func matches(session: RetainedSession, targetVideo: VideoItem) -> Bool {
        if !targetVideo.bvid.isEmpty || !session.video.bvid.isEmpty {
            guard targetVideo.bvid == session.video.bvid else { return false }
        } else if let targetAID = targetVideo.aid, let sessionAID = session.video.aid {
            guard targetAID == sessionAID else { return false }
        } else {
            return targetVideo.id == session.video.id
        }

        if let targetCID = targetVideo.cid, let sessionCID = session.selectedCID {
            return targetCID == sessionCID
        }
        return true
    }

#if DEBUG
    func resetForTesting() {
        stopActiveMiniPlayer()
        supportsPictureInPicture = { AVPictureInPictureController.isPictureInPictureSupported() }
        onStartPictureInPicture = nil
        onAttachStagingSurface = nil
        onDetachStagingSurface = nil
    }
#endif
}

@MainActor
final class SystemMiniPlayerStagingView: UIView {
    let surfaceView = VideoSurfaceContainerView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        surfaceView.backgroundColor = .black
        surfaceView.disablesImplicitLayoutAnimations = true
        surfaceView.configureSurfaceHandoff(
            usesLiveSurfaceDuringLayoutTransition: true,
            isLayoutTransitioning: true
        )
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)
        NSLayoutConstraint.activate([
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

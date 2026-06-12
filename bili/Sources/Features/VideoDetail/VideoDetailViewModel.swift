import Foundation
import Combine
import OSLog
import QuartzCore
import UIKit

@MainActor
final class VideoDetailCommentsRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailCommentsRenderSnapshot()

    var detail: VideoItem? { snapshot.detail }
    var comments: [Comment] { snapshot.comments }
    var commentItems: [VideoDetailCommentDisplayItem] { snapshot.commentItems }
    var state: LoadingState { snapshot.state }
    var selectedSort: CommentSort { snapshot.selectedSort }
    var didCompleteInitialLoad: Bool { snapshot.didCompleteInitialLoad }
    var hasMoreComments: Bool { snapshot.hasMoreComments }
    var shouldShowEmptyCommentsState: Bool { snapshot.shouldShowEmptyCommentsState }
    var shouldShowCommentReloadPrompt: Bool { snapshot.shouldShowCommentReloadPrompt }
    var replyCountText: String? { snapshot.replyCountText }

    func update(
        detail: VideoItem,
        comments: [Comment],
        state: LoadingState,
        selectedSort: CommentSort,
        didCompleteInitialLoad: Bool,
        hasMoreComments: Bool
    ) {
        setSnapshot(
            VideoDetailCommentsRenderSnapshot(
                detail: detail,
                comments: comments,
                state: state,
                selectedSort: selectedSort,
                didCompleteInitialLoad: didCompleteInitialLoad,
                hasMoreComments: hasMoreComments
            )
        )
    }

    func updateDetail(_ detail: VideoItem) {
        updateSnapshot {
            $0.detail = detail
            $0.replyCountText = VideoDetailCommentsRenderSnapshot.makeReplyCountText(detail: detail)
        }
    }

    func updateComments(_ comments: [Comment]) {
        updateSnapshot { $0.setComments(comments) }
    }

    func updateState(_ state: LoadingState) {
        updateSnapshot { $0.state = state }
    }

    func updateSelectedSort(_ selectedSort: CommentSort) {
        updateSnapshot { $0.selectedSort = selectedSort }
    }

    func updateDidCompleteInitialLoad(_ didCompleteInitialLoad: Bool) {
        updateSnapshot { $0.didCompleteInitialLoad = didCompleteInitialLoad }
    }

    func updateHasMoreComments(_ hasMoreComments: Bool) {
        updateSnapshot { $0.hasMoreComments = hasMoreComments }
    }

    private func updateSnapshot(_ transform: (inout VideoDetailCommentsRenderSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        setSnapshot(next)
    }

    private func setSnapshot(_ next: VideoDetailCommentsRenderSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }
}

nonisolated struct VideoDetailCommentDisplayItem: Identifiable, Equatable {
    let id: Int
    let comment: Comment
    let display: VideoDetailCommentDisplayModel

    init(comment: Comment) {
        id = comment.id
        self.comment = comment
        display = VideoDetailCommentDisplayModel(comment: comment)
    }
}

nonisolated struct VideoDetailCommentDisplayModel: Equatable {
    let authorName: String
    let avatarURLString: String?
    let timeText: String
    let likeText: String
    let isLiked: Bool
    let replyPreviews: [Comment]
    let visibleReplyCount: Int
    let pictures: [DynamicImageItem]

    init(comment: Comment) {
        authorName = Self.displayName(comment.member?.uname)
        avatarURLString = comment.member?.avatar
        timeText = BiliFormatters.relativeTime(comment.ctime)
        likeText = BiliFormatters.compactCount(comment.like)
        isLiked = comment.likeState == 1
        replyPreviews = Array((comment.replies ?? []).prefix(2))
        visibleReplyCount = comment.replyCount ?? comment.replies?.count ?? 0
        pictures = comment.content?.pictures ?? []
    }

    private static func displayName(_ name: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Unknown" : trimmedName
    }
}

nonisolated struct VideoDetailCommentReplyDisplayItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: VideoDetailCommentDisplayModel
    let canShowDialog: Bool
}

nonisolated enum VideoDetailCommentReplyDisplayItems {
    static func make(replies: [Comment], rootComment: Comment) -> [VideoDetailCommentReplyDisplayItem] {
        replies.map { reply in
            VideoDetailCommentReplyDisplayItem(
                id: reply.id,
                reply: reply,
                display: VideoDetailCommentDisplayModel(comment: reply),
                canShowDialog: canShowDialog(for: reply, rootComment: rootComment)
            )
        }
    }

    private static func canShowDialog(for reply: Comment, rootComment: Comment) -> Bool {
        guard reply.id != rootComment.id else { return false }
        if let dialogID = reply.dialogID, dialogID > 0 {
            return true
        }
        if let parentID = reply.parentID, parentID > 0, parentID != rootComment.rpid {
            return true
        }
        return hasReplyTarget(in: reply.content?.message)
    }

    private static func hasReplyTarget(in message: String?) -> Bool {
        guard let message else { return false }
        return replyPrefixSplit(in: message.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private static func replyPrefixSplit(in message: String) -> (target: String, separator: String, content: String)? {
        let supportedVerbs = ["回复", "回覆", "回復"]
        guard let verb = supportedVerbs.first(where: { message.hasPrefix($0) }) else { return nil }

        var cursor = message.index(message.startIndex, offsetBy: verb.count)
        while cursor < message.endIndex, message[cursor].isWhitespace {
            cursor = message.index(after: cursor)
        }

        guard cursor < message.endIndex, message[cursor] == "@" else { return nil }
        guard let colon = message[cursor...].firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }

        let prefixEnd = message.index(after: colon)
        let target = String(message[cursor..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = String(message[colon..<prefixEnd])
        let content = String(message[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return (target, separator, content)
    }
}

nonisolated private struct VideoDetailCommentReplyDisplaySignature: Equatable {
    let rootID: Int
    let replies: [Reply]

    init(rootComment: Comment, replies: [Comment]) {
        rootID = rootComment.id
        self.replies = replies.map(Reply.init)
    }

    struct Reply: Equatable {
        let id: Int
        let parentID: Int?
        let dialogID: Int?
        let message: String?

        init(_ reply: Comment) {
            id = reply.id
            parentID = reply.parentID
            dialogID = reply.dialogID
            message = reply.content?.message
        }
    }
}

nonisolated private struct VideoDetailCommentReplyDisplayCacheEntry {
    let signature: VideoDetailCommentReplyDisplaySignature
    let items: [VideoDetailCommentReplyDisplayItem]
}

nonisolated struct VideoDetailCommentDialogDisplayItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: VideoDetailCommentDisplayModel

    init(reply: Comment) {
        id = reply.id
        self.reply = reply
        display = VideoDetailCommentDisplayModel(comment: reply)
    }
}

struct VideoDetailCommentThreadRepliesSnapshot: Equatable {
    let state: LoadingState
    let replies: [Comment]
    let replyDisplays: [VideoDetailCommentReplyDisplayItem]
    let hasMoreReplies: Bool

    var hasLoadedReplies: Bool {
        !replies.isEmpty
    }
}

struct VideoDetailCommentThreadDialogSnapshot: Equatable {
    let state: LoadingState
    let items: [VideoDetailCommentDialogDisplayItem]
}

nonisolated private struct VideoDetailCommentDialogDisplayCacheEntry {
    let signature: VideoDetailCommentReplyDisplaySignature
    let items: [VideoDetailCommentDialogDisplayItem]
}

@MainActor
final class VideoDetailRelatedRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailRelatedRenderSnapshot()

    var related: [VideoItem] { snapshot.related }
    var relatedItems: [VideoDetailRelatedDisplayItem] { snapshot.relatedItems }
    var state: LoadingState { snapshot.state }
    var lastLoadTimedOut: Bool { snapshot.lastLoadTimedOut }

    func update(related: [VideoItem], state: LoadingState, lastLoadTimedOut: Bool) {
        setSnapshot(
            VideoDetailRelatedRenderSnapshot(
                related: related,
                state: state,
                lastLoadTimedOut: lastLoadTimedOut
            )
        )
    }

    func updateRelated(_ related: [VideoItem]) {
        updateSnapshot { $0.related = related }
    }

    func updateState(_ state: LoadingState) {
        updateSnapshot { $0.state = state }
    }

    func updateTimedOut(_ lastLoadTimedOut: Bool) {
        updateSnapshot { $0.lastLoadTimedOut = lastLoadTimedOut }
    }

    private func updateSnapshot(_ transform: (inout VideoDetailRelatedRenderSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        setSnapshot(next)
    }

    private func setSnapshot(_ next: VideoDetailRelatedRenderSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailInteractionRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailInteractionRenderSnapshot()

    var interactionState: VideoInteractionState { snapshot.interactionState }
    var interactionMessage: String? { snapshot.interactionMessage }
    var isMutatingInteraction: Bool { snapshot.isMutatingInteraction }
    var isMutatingLike: Bool { snapshot.isMutatingLike }
    var isMutatingCoin: Bool { snapshot.isMutatingCoin }
    var isMutatingFavorite: Bool { snapshot.isMutatingFavorite }
    var isMutatingFollow: Bool { snapshot.isMutatingFollow }
    var playbackFallbackMessage: String? { snapshot.playbackFallbackMessage }

    func update(
        interactionState: VideoInteractionState,
        interactionMessage: String?,
        isMutatingInteraction: Bool,
        isMutatingLike: Bool,
        isMutatingCoin: Bool,
        isMutatingFavorite: Bool,
        isMutatingFollow: Bool,
        playbackFallbackMessage: String?
    ) {
        setSnapshot(
            VideoDetailInteractionRenderSnapshot(
                interactionState: interactionState,
                interactionMessage: interactionMessage,
                isMutatingInteraction: isMutatingInteraction,
                isMutatingLike: isMutatingLike,
                isMutatingCoin: isMutatingCoin,
                isMutatingFavorite: isMutatingFavorite,
                isMutatingFollow: isMutatingFollow,
                playbackFallbackMessage: playbackFallbackMessage
            )
        )
    }

    private func setSnapshot(_ next: VideoDetailInteractionRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailPlaybackRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlaybackRenderSnapshot()
    let playerSurfaceStore = VideoDetailPlayerSurfaceRenderStore()
    let qualityControlStore = VideoDetailQualityControlRenderStore()
    let placeholderStore = VideoDetailPlayerPlaceholderRenderStore()
    let pageSelectorStore = VideoDetailPageSelectorRenderStore()

    var historyVideo: VideoItem? { snapshot.historyVideo }
    var historyCID: Int? { snapshot.historyCID }
    var duration: TimeInterval? { snapshot.duration }
    var playURLState: LoadingState { snapshot.playURLState }
    var selectedPlayVariant: PlayVariant? { snapshot.selectedPlayVariant }
    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }
    var qualityInlineButtonTitle: String { snapshot.qualityInlineButtonTitle }
    var qualityAccessoryButtonTitle: String { snapshot.qualityAccessoryButtonTitle }
    var qualityButtonSystemImage: String { snapshot.qualityButtonSystemImage }
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] { snapshot.qualityMenuItems }
    var isSupplementingPlayQualities: Bool { snapshot.isSupplementingPlayQualities }
    var isSwitchingPlayQuality: Bool { snapshot.isSwitchingPlayQuality }
    var hasQualityMenu: Bool { !snapshot.qualityMenuItems.isEmpty }

    fileprivate func update(_ next: VideoDetailPlaybackRenderSnapshot) {
        setSnapshot(next)
    }

    private func setSnapshot(_ next: VideoDetailPlaybackRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        playerSurfaceStore.update(VideoDetailPlayerSurfaceRenderSnapshot(playback: next))
        qualityControlStore.update(VideoDetailQualityControlRenderSnapshot(playback: next))
        placeholderStore.update(VideoDetailPlayerPlaceholderRenderSnapshot(playback: next))
        pageSelectorStore.update(VideoDetailPageSelectorRenderSnapshot(playback: next))
    }
}

@MainActor
final class VideoDetailPlayerIdentityRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlayerIdentityRenderSnapshot()

    var playerViewModel: PlayerStateViewModel? { snapshot.playerViewModel }
    var transitionSnapshot: PlaybackTransitionSnapshot? { snapshot.transitionSnapshot }
    var transitionFallbackCoverURL: URL? { snapshot.transitionFallbackCoverURL }
    var transitionPlayerOpacity: Double { snapshot.transitionPlayerOpacity }

    fileprivate func update(_ next: VideoDetailPlayerIdentityRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailPlayerSurfaceRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlayerSurfaceRenderSnapshot()

    var historyVideo: VideoItem? { snapshot.historyVideo }
    var historyCID: Int? { snapshot.historyCID }
    var duration: TimeInterval? { snapshot.duration }
    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }

    fileprivate func update(_ next: VideoDetailPlayerSurfaceRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailQualityControlRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailQualityControlRenderSnapshot()

    var qualityInlineButtonTitle: String { snapshot.qualityInlineButtonTitle }
    var qualityAccessoryButtonTitle: String { snapshot.qualityAccessoryButtonTitle }
    var qualityButtonSystemImage: String { snapshot.qualityButtonSystemImage }
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] { snapshot.qualityMenuItems }
    var isSupplementingPlayQualities: Bool { snapshot.isSupplementingPlayQualities }
    var isSwitchingPlayQuality: Bool { snapshot.isSwitchingPlayQuality }
    var hasQualityMenu: Bool { !snapshot.qualityMenuItems.isEmpty }

    fileprivate func update(_ next: VideoDetailQualityControlRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailPlayerPlaceholderRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlayerPlaceholderRenderSnapshot()

    var playURLState: LoadingState { snapshot.playURLState }
    var selectedPlayVariant: PlayVariant? { snapshot.selectedPlayVariant }
    var isDetailLoading: Bool { snapshot.isDetailLoading }
    var isDetailLoaded: Bool { snapshot.isDetailLoaded }
    var failedMessage: String? { snapshot.failedMessage }

    fileprivate func update(_ next: VideoDetailPlayerPlaceholderRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailPageSelectorRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPageSelectorRenderSnapshot()

    var pages: [VideoPage] { snapshot.pages }
    var selectedCID: Int? { snapshot.selectedCID }
    var pageCountText: String { snapshot.pageCountText }
    var shouldShowPageSelector: Bool { snapshot.shouldShowPageSelector }

    fileprivate func update(_ next: VideoDetailPageSelectorRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailCommentThreadRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailCommentThreadRenderSnapshot()
    private var replyDisplayCache: [Int: VideoDetailCommentReplyDisplayCacheEntry] = [:]
    private var dialogDisplayCache: [String: VideoDetailCommentDialogDisplayCacheEntry] = [:]

    func update(
        replyThreads: [Int: [Comment]],
        replyThreadStates: [Int: LoadingState],
        replyThreadHasMore: [Int: Bool],
        dialogThreads: [String: [Comment]],
        dialogThreadStates: [String: LoadingState]
    ) {
        setSnapshot(
            VideoDetailCommentThreadRenderSnapshot(
                replyThreads: replyThreads,
                replyThreadStates: replyThreadStates,
                replyThreadHasMore: replyThreadHasMore,
                dialogThreads: dialogThreads,
                dialogThreadStates: dialogThreadStates
            )
        )
    }

    func replies(for comment: Comment) -> [Comment] {
        snapshot.replyThreads[comment.id] ?? comment.replies ?? []
    }

    func repliesSnapshot(for comment: Comment) -> VideoDetailCommentThreadRepliesSnapshot {
        let replies = replies(for: comment)
        return VideoDetailCommentThreadRepliesSnapshot(
            state: snapshot.replyThreadStates[comment.id] ?? .idle,
            replies: replies,
            replyDisplays: replyDisplays(for: comment, replies: replies),
            hasMoreReplies: hasMoreReplies(for: comment, loadedCount: replies.count)
        )
    }

    func replyDisplays(for comment: Comment) -> [VideoDetailCommentReplyDisplayItem] {
        replyDisplays(for: comment, replies: replies(for: comment))
    }

    private func replyDisplays(
        for comment: Comment,
        replies: [Comment]
    ) -> [VideoDetailCommentReplyDisplayItem] {
        let signature = VideoDetailCommentReplyDisplaySignature(rootComment: comment, replies: replies)
        if let cached = replyDisplayCache[comment.id], cached.signature == signature {
            return cached.items
        }

        let items = VideoDetailCommentReplyDisplayItems.make(replies: replies, rootComment: comment)
        replyDisplayCache[comment.id] = VideoDetailCommentReplyDisplayCacheEntry(
            signature: signature,
            items: items
        )
        return items
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = snapshot.replyThreadHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        return hasMoreReplies(for: comment, loadedCount: loadedCount)
    }

    private func hasMoreReplies(for comment: Comment, loadedCount: Int) -> Bool {
        if let hasMore = snapshot.replyThreadHasMore[comment.id] {
            return hasMore
        }
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        snapshot.replyThreadStates[comment.id] ?? .idle
    }

    func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
        return dialogReplies(for: root, reply: reply, key: key)
    }

    private func dialogReplies(for root: Comment, reply: Comment, key: String) -> [Comment] {
        return snapshot.dialogThreads[key]
            ?? VideoDetailCommentThreadResolver.localDialogReplies(
                reply,
                siblings: replies(for: root)
            )
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        let key = VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
        return snapshot.dialogThreadStates[key] ?? .idle
    }

    func dialogSnapshot(
        for root: Comment,
        reply: Comment
    ) -> VideoDetailCommentThreadDialogSnapshot {
        let key = VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply, key: key)
        return VideoDetailCommentThreadDialogSnapshot(
            state: snapshot.dialogThreadStates[key] ?? .idle,
            items: dialogDisplays(for: root, key: key, replies: replies)
        )
    }

    private func dialogDisplays(
        for root: Comment,
        key: String,
        replies: [Comment]
    ) -> [VideoDetailCommentDialogDisplayItem] {
        let signature = VideoDetailCommentReplyDisplaySignature(rootComment: root, replies: replies)
        if let cached = dialogDisplayCache[key], cached.signature == signature {
            return cached.items
        }

        let items = replies.map(VideoDetailCommentDialogDisplayItem.init(reply:))
        dialogDisplayCache[key] = VideoDetailCommentDialogDisplayCacheEntry(
            signature: signature,
            items: items
        )
        return items
    }

    private func setSnapshot(_ next: VideoDetailCommentThreadRenderSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailFavoriteFolderRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailFavoriteFolderRenderSnapshot()

    var favoriteFolders: [FavoriteFolder] { snapshot.favoriteFolders }
    var favoriteFolderState: LoadingState { snapshot.favoriteFolderState }
    var isMutatingInteraction: Bool { snapshot.isMutatingInteraction }

    func update(_ next: VideoDetailFavoriteFolderRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailDanmakuSettingsRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailDanmakuSettingsRenderSnapshot()

    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }
    var danmakuSettings: DanmakuSettings { snapshot.danmakuSettings }

    func update(_ next: VideoDetailDanmakuSettingsRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailDanmakuRenderStore: ObservableObject {
    @Published private(set) var snapshot = VideoDetailDanmakuRenderSnapshot()

    var items: [DanmakuItem] { snapshot.items }
    var itemsRevision: Int { snapshot.itemsRevision }
    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }
    var effectiveSettings: DanmakuSettings { snapshot.effectiveSettings }

    fileprivate func update(_ next: VideoDetailDanmakuRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailNetworkDiagnosticsRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailNetworkDiagnosticsRenderSnapshot()

    var videoTitle: String { snapshot.videoTitle }
    var metricsID: String { snapshot.metricsID }
    var selectedPlayVariant: PlayVariant? { snapshot.selectedPlayVariant }
    var playerViewModel: PlayerStateViewModel? { snapshot.playerViewModel }
    var detailLoadElapsedMilliseconds: Int? { snapshot.detailLoadElapsedMilliseconds }
    var playURLElapsedMilliseconds: Int? { snapshot.playURLElapsedMilliseconds }
    var relatedElapsedMilliseconds: Int? { snapshot.relatedElapsedMilliseconds }
    var lastPlayURLSource: String? { snapshot.lastPlayURLSource }
    var resumeDiagnostics: PlaybackResumeDiagnostics { snapshot.resumeDiagnostics }
    var playbackFallbackMessage: String? { snapshot.playbackFallbackMessage }

    func update(_ next: VideoDetailNetworkDiagnosticsRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailDescriptionRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailDescriptionRenderSnapshot()

    var titleText: String { snapshot.titleText }
    var owner: VideoOwner? { snapshot.owner }
    var viewCountText: String { snapshot.viewCountText }
    var fanCountText: String { snapshot.fanCountText }
    var publishDateText: String { snapshot.publishDateText }
    var publishDateSubtitleText: String? { snapshot.publishDateSubtitleText }
    var descriptionText: String { snapshot.descriptionText }
    var hasResolvedDetailMetadata: Bool { snapshot.hasResolvedDetailMetadata }
    var canFavorite: Bool { snapshot.canFavorite }
    var shareURL: URL? { snapshot.shareURL }
    var shareSubject: String { snapshot.shareSubject }
    var shareMessage: String { snapshot.shareMessage }
    var isFollowing: Bool { snapshot.isFollowing }
    var isMutatingInteraction: Bool { snapshot.isMutatingInteraction }

    func update(_ next: VideoDetailDescriptionRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

private struct VideoDetailCommentsRenderSnapshot: Equatable {
    var detail: VideoItem?
    var comments: [Comment]
    var commentItems: [VideoDetailCommentDisplayItem]
    var state: LoadingState
    var selectedSort: CommentSort
    var didCompleteInitialLoad: Bool
    var hasMoreComments: Bool
    var replyCountText: String?
    private(set) var commentsSignature: VideoDetailCommentListSignature

    init(
        detail: VideoItem? = nil,
        comments: [Comment] = [],
        state: LoadingState = .idle,
        selectedSort: CommentSort = .hot,
        didCompleteInitialLoad: Bool = false,
        hasMoreComments: Bool = false,
        replyCountText: String? = nil
    ) {
        self.detail = detail
        self.comments = comments
        self.commentItems = Self.makeCommentItems(comments)
        self.commentsSignature = VideoDetailCommentListSignature(comments)
        self.state = state
        self.selectedSort = selectedSort
        self.didCompleteInitialLoad = didCompleteInitialLoad
        self.hasMoreComments = hasMoreComments
        self.replyCountText = replyCountText ?? Self.makeReplyCountText(detail: detail)
    }

    var changeSignature: VideoDetailCommentsRenderChangeSignature {
        VideoDetailCommentsRenderChangeSignature(
            detailBVID: detail?.bvid,
            detailReplyCount: detail?.stat?.reply,
            commentsSignature: commentsSignature,
            state: state,
            selectedSort: selectedSort,
            didCompleteInitialLoad: didCompleteInitialLoad,
            hasMoreComments: hasMoreComments,
            replyCountText: replyCountText
        )
    }

    var shouldShowEmptyCommentsState: Bool {
        guard didCompleteInitialLoad,
              comments.isEmpty,
              state == .loaded
        else { return false }
        if let replyCount = detail?.stat?.reply {
            return replyCount == 0 && !hasMoreComments
        }
        return !hasMoreComments
    }

    var shouldShowCommentReloadPrompt: Bool {
        didCompleteInitialLoad
            && comments.isEmpty
            && state == .loaded
            && !shouldShowEmptyCommentsState
    }

    mutating func setComments(_ comments: [Comment]) {
        self.comments = comments
        commentItems = Self.makeCommentItems(comments)
        commentsSignature = VideoDetailCommentListSignature(comments)
    }

    private static func makeCommentItems(_ comments: [Comment]) -> [VideoDetailCommentDisplayItem] {
        comments.map(VideoDetailCommentDisplayItem.init(comment:))
    }

    fileprivate static func makeReplyCountText(detail: VideoItem?) -> String? {
        guard let reply = detail?.stat?.reply else { return nil }
        return BiliFormatters.compactCount(reply)
    }
}

nonisolated private struct VideoDetailCommentsRenderChangeSignature: Equatable {
    let detailBVID: String?
    let detailReplyCount: Int?
    let commentsSignature: VideoDetailCommentListSignature
    let state: LoadingState
    let selectedSort: CommentSort
    let didCompleteInitialLoad: Bool
    let hasMoreComments: Bool
    let replyCountText: String?
}

nonisolated private struct VideoDetailCommentListSignature: Equatable {
    let items: [VideoDetailCommentSignature]

    init(_ comments: [Comment]) {
        items = comments.map(VideoDetailCommentSignature.init)
    }
}

nonisolated private struct VideoDetailCommentSignature: Equatable {
    let id: Int
    let parentID: Int?
    let dialogID: Int?
    let authorName: String?
    let avatar: String?
    let message: String?
    let like: Int?
    let ctime: Int?
    let replyCount: Int?
    let likeState: Int?
    let pictureURLs: [String]
    let replyPreviews: [VideoDetailCommentReplyPreviewSignature]

    init(_ comment: Comment) {
        id = comment.id
        parentID = comment.parentID
        dialogID = comment.dialogID
        authorName = comment.member?.uname
        avatar = comment.member?.avatar
        message = comment.content?.message
        like = comment.like
        ctime = comment.ctime
        replyCount = comment.replyCount
        likeState = comment.likeState
        pictureURLs = (comment.content?.pictures ?? []).map(\.url)
        replyPreviews = (comment.replies ?? [])
            .prefix(2)
            .map(VideoDetailCommentReplyPreviewSignature.init)
    }
}

nonisolated private struct VideoDetailCommentReplyPreviewSignature: Equatable {
    let id: Int
    let authorName: String?
    let message: String?

    init(_ comment: Comment) {
        id = comment.id
        authorName = comment.member?.uname
        message = comment.content?.message
    }
}

private struct VideoDetailRelatedRenderSnapshot: Equatable {
    var related: [VideoItem] = [] {
        didSet {
            relatedItems = related.map(VideoDetailRelatedDisplayItem.init(video:))
            relatedSignature = VideoDetailRelatedListSignature(related)
        }
    }
    var relatedItems: [VideoDetailRelatedDisplayItem] = []
    private var relatedSignature = VideoDetailRelatedListSignature([])
    var state: LoadingState = .idle
    var lastLoadTimedOut = false

    init() {}

    init(
        related: [VideoItem],
        state: LoadingState,
        lastLoadTimedOut: Bool
    ) {
        self.related = related
        relatedItems = related.map(VideoDetailRelatedDisplayItem.init(video:))
        relatedSignature = VideoDetailRelatedListSignature(related)
        self.state = state
        self.lastLoadTimedOut = lastLoadTimedOut
    }

    var changeSignature: VideoDetailRelatedRenderChangeSignature {
        VideoDetailRelatedRenderChangeSignature(
            relatedSignature: relatedSignature,
            state: state,
            lastLoadTimedOut: lastLoadTimedOut
        )
    }
}

nonisolated private struct VideoDetailRelatedRenderChangeSignature: Equatable {
    let relatedSignature: VideoDetailRelatedListSignature
    let state: LoadingState
    let lastLoadTimedOut: Bool
}

nonisolated private struct VideoDetailRelatedListSignature: Equatable {
    let items: [VideoDetailRelatedItemSignature]

    init(_ videos: [VideoItem]) {
        items = videos.map(VideoDetailRelatedItemSignature.init)
    }
}

nonisolated private struct VideoDetailRelatedItemSignature: Equatable {
    let id: String
    let title: String
    let coverURL: String?
    let duration: Int?
    let ownerID: Int?
    let ownerName: String?
    let viewCount: Int?
    let pubdate: Int?

    init(_ video: VideoItem) {
        id = video.id
        title = video.title
        coverURL = video.pic
        duration = video.duration
        ownerID = video.owner?.mid
        ownerName = video.owner?.name
        viewCount = video.stat?.view
        pubdate = video.pubdate
    }
}

nonisolated struct VideoDetailRelatedDisplayItem: Identifiable, Equatable {
    let id: String
    let video: VideoItem
    let display: VideoCardDisplayModel

    init(video: VideoItem) {
        id = video.id
        self.video = video
        display = VideoCardDisplayModel(video: video)
    }
}

private struct VideoDetailInteractionRenderSnapshot: Equatable {
    var interactionState = VideoInteractionState()
    var interactionMessage: String?
    var isMutatingInteraction = false
    var isMutatingLike = false
    var isMutatingCoin = false
    var isMutatingFavorite = false
    var isMutatingFollow = false
    var playbackFallbackMessage: String?
}

private struct VideoDetailPlayerIdentityRenderSnapshot: Equatable {
    var playerViewModel: PlayerStateViewModel?
    var transitionSnapshot: PlaybackTransitionSnapshot?
    var transitionFallbackCoverURL: URL?
    var transitionPlayerOpacity = 0.0

    static func == (
        lhs: VideoDetailPlayerIdentityRenderSnapshot,
        rhs: VideoDetailPlayerIdentityRenderSnapshot
    ) -> Bool {
        isSamePlayer(lhs.playerViewModel, rhs.playerViewModel)
            && isSameSnapshot(lhs.transitionSnapshot, rhs.transitionSnapshot)
            && lhs.transitionFallbackCoverURL == rhs.transitionFallbackCoverURL
            && abs(lhs.transitionPlayerOpacity - rhs.transitionPlayerOpacity) < 0.001
    }

    private static func isSamePlayer(_ lhs: PlayerStateViewModel?, _ rhs: PlayerStateViewModel?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return left === right
        default:
            return false
        }
    }

    private static func isSameSnapshot(_ lhs: PlaybackTransitionSnapshot?, _ rhs: PlaybackTransitionSnapshot?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return left.image === right.image
        default:
            return false
        }
    }
}

private struct VideoDetailPlayerSurfaceRenderSnapshot: Equatable {
    var historyVideo: VideoItem?
    var historyCID: Int?
    var duration: TimeInterval?
    var isDanmakuEnabled = true

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        historyVideo = playback.historyVideo
        historyCID = playback.historyCID
        duration = playback.duration
        isDanmakuEnabled = playback.isDanmakuEnabled
    }
}

private struct VideoDetailQualityControlRenderSnapshot: Equatable {
    var qualityInlineButtonTitle = "清晰度"
    var qualityAccessoryButtonTitle = "清晰度"
    var qualityButtonSystemImage = "slider.horizontal.3"
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] = []
    var isSupplementingPlayQualities = false
    var isSwitchingPlayQuality = false

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        qualityInlineButtonTitle = playback.qualityInlineButtonTitle
        qualityAccessoryButtonTitle = playback.qualityAccessoryButtonTitle
        qualityButtonSystemImage = playback.qualityButtonSystemImage
        qualityMenuItems = playback.qualityMenuItems
        isSupplementingPlayQualities = playback.isSupplementingPlayQualities
        isSwitchingPlayQuality = playback.isSwitchingPlayQuality
    }
}

private struct VideoDetailPlayerPlaceholderRenderSnapshot: Equatable {
    var playURLState: LoadingState = .idle
    var selectedPlayVariant: PlayVariant?
    var isDetailLoading = false
    var isDetailLoaded = false
    var failedMessage: String?

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        playURLState = playback.playURLState
        selectedPlayVariant = playback.selectedPlayVariant
        isDetailLoading = playback.isDetailLoading
        isDetailLoaded = playback.isDetailLoaded
        failedMessage = playback.failedMessage
    }
}

private struct VideoDetailPageSelectorRenderSnapshot: Equatable {
    var pages: [VideoPage] = []
    var selectedCID: Int?
    var pageCountText = "0P"

    var shouldShowPageSelector: Bool {
        pages.count > 1
    }

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        pages = playback.pages
        selectedCID = playback.selectedCID
        pageCountText = "\(playback.pages.count)P"
    }
}

private struct VideoDetailPlaybackRenderSnapshot: Equatable {
    var historyVideo: VideoItem?
    var historyCID: Int?
    var duration: TimeInterval?
    var pages: [VideoPage] = []
    var selectedCID: Int?
    var playURLState: LoadingState = .idle
    var selectedPlayVariant: PlayVariant?
    var isDetailLoading = false
    var isDetailLoaded = false
    var failedMessage: String?
    var isDanmakuEnabled = true
    var qualityInlineButtonTitle = "清晰度"
    var qualityAccessoryButtonTitle = "清晰度"
    var qualityButtonSystemImage = "slider.horizontal.3"
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] = []
    var isSupplementingPlayQualities = false
    var isSwitchingPlayQuality = false

    init(
        historyVideo: VideoItem? = nil,
        historyCID: Int? = nil,
        duration: TimeInterval? = nil,
        pages: [VideoPage] = [],
        selectedCID: Int? = nil,
        playURLState: LoadingState = .idle,
        selectedPlayVariant: PlayVariant? = nil,
        isDetailLoading: Bool = false,
        isDetailLoaded: Bool = false,
        failedMessage: String? = nil,
        isDanmakuEnabled: Bool = true,
        qualityInlineButtonTitle: String = "清晰度",
        qualityAccessoryButtonTitle: String = "清晰度",
        qualityButtonSystemImage: String = "slider.horizontal.3",
        qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] = [],
        isSupplementingPlayQualities: Bool = false,
        isSwitchingPlayQuality: Bool = false
    ) {
        self.historyVideo = historyVideo
        self.historyCID = historyCID
        self.duration = duration
        self.pages = pages
        self.selectedCID = selectedCID
        self.playURLState = playURLState
        self.selectedPlayVariant = selectedPlayVariant
        self.isDetailLoading = isDetailLoading
        self.isDetailLoaded = isDetailLoaded
        self.failedMessage = failedMessage
        self.isDanmakuEnabled = isDanmakuEnabled
        self.qualityInlineButtonTitle = qualityInlineButtonTitle
        self.qualityAccessoryButtonTitle = qualityAccessoryButtonTitle
        self.qualityButtonSystemImage = qualityButtonSystemImage
        self.qualityMenuItems = qualityMenuItems
        self.isSupplementingPlayQualities = isSupplementingPlayQualities
        self.isSwitchingPlayQuality = isSwitchingPlayQuality
    }

    init(viewModel: VideoDetailViewModel) {
        let currentPlayVariant = viewModel.selectedPlayVariant
        let isSupplementingPlayQualities = viewModel.isSupplementingPlayQualities
        let isSwitchingPlayQuality = viewModel.isSwitchingPlayQuality

        self.historyVideo = viewModel.detail
        self.historyCID = viewModel.selectedCID
        self.duration = viewModel.detail.duration.map(TimeInterval.init)
        self.pages = viewModel.detail.pages ?? []
        self.selectedCID = viewModel.selectedCID
        self.playURLState = viewModel.playURLState
        self.selectedPlayVariant = currentPlayVariant
        self.isDetailLoading = viewModel.state.isLoading
        self.isDetailLoaded = viewModel.state == .loaded
        if case let .failed(message) = viewModel.state {
            self.failedMessage = message
        } else {
            self.failedMessage = nil
        }
        self.isDanmakuEnabled = viewModel.isDanmakuEnabled
        qualityInlineButtonTitle = Self.inlineQualityButtonTitle(
            selectedPlayVariant: currentPlayVariant,
            isSupplementingPlayQualities: isSupplementingPlayQualities,
            isSwitchingPlayQuality: isSwitchingPlayQuality
        )
        qualityAccessoryButtonTitle = Self.accessoryQualityButtonTitle(
            selectedPlayVariant: currentPlayVariant,
            isSupplementingPlayQualities: isSupplementingPlayQualities,
            isSwitchingPlayQuality: isSwitchingPlayQuality
        )
        qualityButtonSystemImage = isSwitchingPlayQuality
            ? "arrow.triangle.2.circlepath"
            : "slider.horizontal.3"
        qualityMenuItems = Self.makeQualityMenuItems(
            playVariants: viewModel.playVariants,
            selectedPlayVariant: currentPlayVariant,
            pendingPlayVariantID: viewModel.pendingPlayVariantID,
            isSwitchingPlayQuality: isSwitchingPlayQuality
        )
        self.isSupplementingPlayQualities = isSupplementingPlayQualities
        self.isSwitchingPlayQuality = isSwitchingPlayQuality
    }

    private static func inlineQualityButtonTitle(
        selectedPlayVariant: PlayVariant?,
        isSupplementingPlayQualities: Bool,
        isSwitchingPlayQuality: Bool
    ) -> String {
        if isSwitchingPlayQuality {
            return "切换中"
        }
        return selectedPlayVariant?.title ?? "清晰度"
    }

    private static func accessoryQualityButtonTitle(
        selectedPlayVariant: PlayVariant?,
        isSupplementingPlayQualities: Bool,
        isSwitchingPlayQuality: Bool
    ) -> String {
        if isSwitchingPlayQuality {
            return "切换中"
        }
        return selectedPlayVariant?.compactAccessoryTitle ?? "清晰度"
    }

    private static func makeQualityMenuItems(
        playVariants: [PlayVariant],
        selectedPlayVariant: PlayVariant?,
        pendingPlayVariantID: String?,
        isSwitchingPlayQuality: Bool
    ) -> [VideoDetailPlaybackQualityMenuItem] {
        playVariants.map { variant in
            let systemImage: String
            if pendingPlayVariantID == variant.id {
                systemImage = "arrow.triangle.2.circlepath"
            } else if selectedPlayVariant == variant {
                systemImage = "checkmark"
            } else {
                systemImage = variant.isPlayable ? "circle" : "lock.fill"
            }
            return VideoDetailPlaybackQualityMenuItem(
                variant: variant,
                title: variant.qualityMenuTitle,
                systemImage: systemImage,
                isDisabled: !variant.isPlayable || isSwitchingPlayQuality
            )
        }
    }
}

private struct VideoDetailCommentThreadRenderSnapshot: Equatable {
    var replyThreads: [Int: [Comment]] = [:]
    var replyThreadStates: [Int: LoadingState] = [:]
    var replyThreadHasMore: [Int: Bool] = [:]
    var dialogThreads: [String: [Comment]] = [:]
    var dialogThreadStates: [String: LoadingState] = [:]

    var changeSignature: VideoDetailCommentThreadRenderChangeSignature {
        VideoDetailCommentThreadRenderChangeSignature(
            replyThreadSignatures: replyThreads.mapValues(VideoDetailCommentListSignature.init),
            replyThreadStates: replyThreadStates,
            replyThreadHasMore: replyThreadHasMore,
            dialogThreadSignatures: dialogThreads.mapValues(VideoDetailCommentListSignature.init),
            dialogThreadStates: dialogThreadStates
        )
    }
}

nonisolated private struct VideoDetailCommentThreadRenderChangeSignature: Equatable {
    let replyThreadSignatures: [Int: VideoDetailCommentListSignature]
    let replyThreadStates: [Int: LoadingState]
    let replyThreadHasMore: [Int: Bool]
    let dialogThreadSignatures: [String: VideoDetailCommentListSignature]
    let dialogThreadStates: [String: LoadingState]
}

struct VideoDetailFavoriteFolderRenderSnapshot: Equatable {
    var favoriteFolders: [FavoriteFolder] = []
    var favoriteFolderState: LoadingState = .idle
    var isMutatingInteraction = false

    init() {}

    init(viewModel: VideoDetailViewModel) {
        favoriteFolders = viewModel.favoriteFolders
        favoriteFolderState = viewModel.favoriteFolderState
        isMutatingInteraction = viewModel.isMutatingFavorite
    }
}

struct VideoDetailDanmakuSettingsRenderSnapshot: Equatable {
    var isDanmakuEnabled = true
    var danmakuSettings = DanmakuSettings.default

    init() {}

    init(viewModel: VideoDetailViewModel) {
        isDanmakuEnabled = viewModel.isDanmakuEnabled
        danmakuSettings = viewModel.danmakuSettings
    }
}

struct VideoDetailDanmakuRenderSnapshot: Equatable {
    var items: [DanmakuItem] = []
    var itemsRevision = 0
    var isDanmakuEnabled = true
    var effectiveSettings = DanmakuSettings.default

    init() {}

    init(viewModel: VideoDetailViewModel) {
        items = viewModel.danmakuItems
        itemsRevision = viewModel.danmakuItemsRevision
        isDanmakuEnabled = viewModel.isDanmakuEnabled
        effectiveSettings = viewModel.effectiveDanmakuSettings
    }

    static func == (
        lhs: VideoDetailDanmakuRenderSnapshot,
        rhs: VideoDetailDanmakuRenderSnapshot
    ) -> Bool {
        lhs.itemsRevision == rhs.itemsRevision
            && lhs.isDanmakuEnabled == rhs.isDanmakuEnabled
            && lhs.effectiveSettings == rhs.effectiveSettings
    }
}

struct VideoDetailNetworkDiagnosticsRenderSnapshot: Equatable {
    var videoTitle = ""
    var metricsID = ""
    var selectedPlayVariant: PlayVariant?
    var playerViewModel: PlayerStateViewModel?
    var detailLoadElapsedMilliseconds: Int?
    var playURLElapsedMilliseconds: Int?
    var relatedElapsedMilliseconds: Int?
    var lastPlayURLSource: String?
    var resumeDiagnostics = PlaybackResumeDiagnostics.none
    var playbackFallbackMessage: String?

    init() {}

    init(viewModel: VideoDetailViewModel) {
        videoTitle = viewModel.detail.title
        metricsID = viewModel.detail.bvid
        selectedPlayVariant = viewModel.selectedPlayVariant
        playerViewModel = viewModel.stablePlayerViewModel
        detailLoadElapsedMilliseconds = viewModel.detailLoadElapsedMilliseconds
        playURLElapsedMilliseconds = viewModel.playURLElapsedMilliseconds
        relatedElapsedMilliseconds = viewModel.relatedElapsedMilliseconds
        lastPlayURLSource = viewModel.lastPlayURLSource
        resumeDiagnostics = viewModel.resumeDiagnostics
        playbackFallbackMessage = viewModel.playbackFallbackMessage
    }

    static func == (lhs: VideoDetailNetworkDiagnosticsRenderSnapshot, rhs: VideoDetailNetworkDiagnosticsRenderSnapshot) -> Bool {
        lhs.videoTitle == rhs.videoTitle
            && lhs.metricsID == rhs.metricsID
            && lhs.selectedPlayVariant == rhs.selectedPlayVariant
            && samePlayer(lhs.playerViewModel, rhs.playerViewModel)
            && lhs.detailLoadElapsedMilliseconds == rhs.detailLoadElapsedMilliseconds
            && lhs.playURLElapsedMilliseconds == rhs.playURLElapsedMilliseconds
            && lhs.relatedElapsedMilliseconds == rhs.relatedElapsedMilliseconds
            && lhs.lastPlayURLSource == rhs.lastPlayURLSource
            && lhs.resumeDiagnostics == rhs.resumeDiagnostics
            && lhs.playbackFallbackMessage == rhs.playbackFallbackMessage
    }

    private static func samePlayer(_ lhs: PlayerStateViewModel?, _ rhs: PlayerStateViewModel?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return left === right
        default:
            return false
        }
    }
}

struct VideoDetailDescriptionRenderSnapshot: Equatable {
    var titleText = ""
    var owner: VideoOwner?
    var viewCountText = "-"
    var fanCountText = "粉丝 -"
    var publishDateText = "-"
    var publishDateSubtitleText: String?
    var descriptionText = "这个视频暂时没有简介。"
    var hasResolvedDetailMetadata = false
    var canFavorite = false
    var shareURL: URL?
    var shareSubject = ""
    var shareMessage = "来自哔哩哔哩的视频"
    var isFollowing = false
    var isMutatingInteraction = false

    init() {}

    init(viewModel: VideoDetailViewModel) {
        let detail = viewModel.detail
        let trimmedTitle = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)

        titleText = detail.title
        owner = detail.owner
        viewCountText = BiliFormatters.compactCount(detail.stat?.view)
        fanCountText = viewModel.uploaderFanCountText
        publishDateText = viewModel.detailDisplayMetrics.publishDateText
        publishDateSubtitleText = viewModel.detailDisplayMetrics.publishDateSubtitleText
        let description = (detail.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionText = description.isEmpty ? "这个视频暂时没有简介。" : description
        hasResolvedDetailMetadata = viewModel.hasResolvedDetailMetadata
        canFavorite = viewModel.detailDisplayMetrics.canFavorite
        shareURL = Self.videoShareURL(for: detail)
        shareSubject = trimmedTitle
        shareMessage = trimmedTitle.isEmpty ? "来自哔哩哔哩的视频" : trimmedTitle
        isFollowing = viewModel.interactionState.isFollowing
        isMutatingInteraction = viewModel.isMutatingFollow
    }

    private static func videoShareURL(for video: VideoItem) -> URL? {
        let bvid = video.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bvid.isEmpty else { return nil }
        return URL(string: "https://www.bilibili.com/video/\(bvid)")
    }
}

struct VideoDetailPlaybackQualityMenuItem: Identifiable, Equatable {
    let variant: PlayVariant
    let title: String
    let systemImage: String
    let isDisabled: Bool

    var id: String { variant.id }
}

struct PlaybackResumeDiagnostics: Equatable {
    let sourceTitle: String
    let targetTime: TimeInterval?
    let cid: Int?
    let statusTitle: String
    let reason: String
    let currentTime: TimeInterval?

    static let none = PlaybackResumeDiagnostics(
        sourceTitle: "无",
        targetTime: nil,
        cid: nil,
        statusTitle: "从头播放",
        reason: "没有可用历史进度",
        currentTime: nil
    )
}

private struct PlaybackResumeCandidate {
    let time: TimeInterval
    let sourceTitle: String
    let reason: String
    let cid: Int?
}

private enum VideoDetailCommentThreadResolver {
    static func dialogKey(root: Comment, reply: Comment) -> String {
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            return "\(root.id)-\(dialogID)"
        }
        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            return "\(root.id)-p-\(parentID)-\(reply.id)"
        }
        return "\(root.id)-r-\(reply.id)"
    }

    static func localDialogReplies(_ reply: Comment, siblings: [Comment]) -> [Comment] {
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            let matches = siblings.filter {
                $0.dialogID == dialogID || $0.id == dialogID || $0.parentID == dialogID
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            let matches = siblings.filter {
                $0.parentID == parentID || $0.id == parentID || $0.id == reply.id
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        return [reply]
    }

    static func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<Int>()
        return comments.filter { seen.insert($0.id).inserted }
    }
}

struct VideoDetailDisplayMetrics: Equatable {
    var publishDateText = "-"
    var publishDateSubtitleText: String?
    var likeTitle = "-"
    var coinTitle = "-"
    var favoriteTitle = "-"
    var canFavorite = false

    init() {}

    init(video: VideoItem) {
        publishDateText = BiliFormatters.publishDate(video.pubdate)
        publishDateSubtitleText = publishDateText == "-" ? nil : "投稿于 \(publishDateText)"
        likeTitle = BiliFormatters.compactCount(video.stat?.like)
        coinTitle = BiliFormatters.compactCount(video.stat?.coin)
        favoriteTitle = BiliFormatters.compactCount(video.stat?.favorite)
        canFavorite = video.aid != nil
    }
}

@MainActor
final class VideoDetailViewModel: ObservableObject {
    private enum InteractionMutationKind: Equatable {
        case like
        case coin
        case favorite
        case follow
    }

    private enum PlaybackStartupRelease {
        case firstFrame
        case failed
    }

    private struct PlaybackStartupWaiter {
        let acceptsFailure: Bool
        let continuation: CheckedContinuation<PlaybackStartupRelease?, Never>
    }

    private enum PlayURLLoadMode {
        case normal
        case playbackRecovery

        var startMessage: String {
            switch self {
            case .normal:
                return "start"
            case .playbackRecovery:
                return "start recovery"
            }
        }

        var allowsStartupCache: Bool {
            switch self {
            case .normal:
                return true
            case .playbackRecovery:
                return false
            }
        }

        var allowsNetworkFailureCacheFallback: Bool {
            switch self {
            case .normal:
                return true
            case .playbackRecovery:
                return false
            }
        }
    }

    private struct RenderStoreSyncMask: OptionSet {
        let rawValue: Int

        static let interaction = RenderStoreSyncMask(rawValue: 1 << 0)
        static let playback = RenderStoreSyncMask(rawValue: 1 << 1)
        static let favoriteFolder = RenderStoreSyncMask(rawValue: 1 << 2)
        static let danmakuSettings = RenderStoreSyncMask(rawValue: 1 << 3)
        static let networkDiagnostics = RenderStoreSyncMask(rawValue: 1 << 4)
        static let description = RenderStoreSyncMask(rawValue: 1 << 5)
        static let playerIdentity = RenderStoreSyncMask(rawValue: 1 << 6)
        static let danmaku = RenderStoreSyncMask(rawValue: 1 << 7)
    }

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
    let commentsRenderStore = VideoDetailCommentsRenderStore()
    let relatedRenderStore = VideoDetailRelatedRenderStore()
    let interactionRenderStore = VideoDetailInteractionRenderStore()
    let playbackRenderStore = VideoDetailPlaybackRenderStore()
    let commentThreadRenderStore = VideoDetailCommentThreadRenderStore()
    let favoriteFolderRenderStore = VideoDetailFavoriteFolderRenderStore()
    let danmakuSettingsRenderStore = VideoDetailDanmakuSettingsRenderStore()
    let danmakuRenderStore = VideoDetailDanmakuRenderStore()
    let networkDiagnosticsRenderStore = VideoDetailNetworkDiagnosticsRenderStore()
    let descriptionRenderStore = VideoDetailDescriptionRenderStore()
    let playerIdentityRenderStore = VideoDetailPlayerIdentityRenderStore()
    private(set) var detailDisplayMetrics = VideoDetailDisplayMetrics()
    private(set) var related: [VideoItem] = [] {
        didSet {
            relatedRenderStore.updateRelated(related)
        }
    }
    private(set) var relatedState: LoadingState = .idle {
        didSet {
            relatedRenderStore.updateState(relatedState)
        }
    }
    private(set) var comments: [Comment] = [] {
        didSet {
            commentsRenderStore.updateComments(comments)
        }
    }
    private var uploaderProfile: UploaderProfile? {
        didSet {
            refreshUploaderFanCountText()
        }
    }
    private(set) var uploaderFanCountText = "粉丝 -" {
        didSet { scheduleRenderStoreSync(.description) }
    }
    @Published var selectedCID: Int? { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var state: LoadingState = .idle {
        didSet { scheduleRenderStoreSync(.playback) }
    }
    private(set) var commentState: LoadingState = .idle {
        didSet {
            commentsRenderStore.updateState(commentState)
        }
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
    @Published private(set) var isSwitchingPlayQuality = false { didSet { scheduleRenderStoreSync(.playback) } }
    @Published private(set) var pendingPlayVariantID: String? { didSet { scheduleRenderStoreSync(.playback) } }
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
    private(set) var isMutatingLike = false {
        didSet {
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync(.interaction)
        }
    }
    private(set) var isMutatingCoin = false {
        didSet {
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync(.interaction)
        }
    }
    private(set) var isMutatingFavorite = false {
        didSet {
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync([.interaction, .favoriteFolder])
        }
    }
    private(set) var isMutatingFollow = false {
        didSet {
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync([.interaction, .description])
        }
    }
    @Published var favoriteFolders: [FavoriteFolder] = [] {
        didSet { scheduleRenderStoreSync(.favoriteFolder) }
    }
    @Published var favoriteFolderState: LoadingState = .idle {
        didSet { scheduleRenderStoreSync(.favoriteFolder) }
    }
    private(set) var didCompleteInitialCommentLoad = false {
        didSet {
            commentsRenderStore.updateDidCompleteInitialLoad(didCompleteInitialCommentLoad)
        }
    }
    @Published private(set) var stablePlayerViewModel: PlayerStateViewModel? {
        didSet { scheduleRenderStoreSync([.networkDiagnostics, .playerIdentity]) }
    }
    private(set) var selectedCommentSort: CommentSort = .hot {
        didSet {
            commentsRenderStore.updateSelectedSort(selectedCommentSort)
        }
    }
    @Published var playbackFallbackMessage: String? {
        didSet {
            scheduleRenderStoreSync([.interaction, .networkDiagnostics])
        }
    }
    @Published private(set) var danmakuItems: [DanmakuItem] = []
    @Published private(set) var danmakuItemsRevision = 0
    @Published private(set) var danmakuState: LoadingState = .idle
    @Published var isDanmakuEnabled = true {
        didSet {
            scheduleRenderStoreSync([.playback, .danmakuSettings, .danmaku])
        }
    }
    @Published var danmakuSettings: DanmakuSettings = .default {
        didSet { scheduleRenderStoreSync([.danmakuSettings, .danmaku]) }
    }
    @Published private(set) var detailLoadElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published private(set) var playURLElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published private(set) var relatedElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published private(set) var lastPlayURLSource: String? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    private(set) var lastRelatedLoadTimedOut = false {
        didSet {
            relatedRenderStore.updateTimedOut(lastRelatedLoadTimedOut)
        }
    }
    @Published private(set) var resumeDiagnostics: PlaybackResumeDiagnostics = .none {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    private var replyThreads: [Int: [Comment]] = [:] {
        didSet { syncCommentThreadRenderStore() }
    }
    private var replyThreadStates: [Int: LoadingState] = [:] {
        didSet { syncCommentThreadRenderStore() }
    }
    private var replyThreadPages: [Int: Int] = [:]
    private var replyThreadHasMore: [Int: Bool] = [:] {
        didSet { syncCommentThreadRenderStore() }
    }
    private var dialogThreads: [String: [Comment]] = [:] {
        didSet { syncCommentThreadRenderStore() }
    }
    private var dialogThreadStates: [String: LoadingState] = [:] {
        didSet { syncCommentThreadRenderStore() }
    }

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private let sponsorBlockService: SponsorBlockService
    private var commentCursor = ""
    private var commentsEnd = false {
        didSet {
            commentsRenderStore.updateHasMoreComments(!commentsEnd)
        }
    }
    private var backgroundTasks = [UUID: Task<Void, Never>]()
    private var pageLoadingTask: Task<Void, Never>?
    private var detailLoadingTask: Task<Void, Never>?
    private var detailLoadingToken: UUID?
    private var playURLSupplementTask: Task<Void, Never>?
    private var playVariantSwitchTask: Task<Void, Never>?
    private var commentsLoadingTask: Task<Void, Never>?
    private var commentsLoadingToken: UUID?
    private var startupPlayURLTask: Task<PlayURLData, Error>?
    private var startupPlayURLTaskKey: String?
    private var relatedLoadingTask: Task<Void, Never>?
    private var relatedRefreshTask: Task<Void, Never>?
    private var relatedPreloadTask: Task<Void, Never>?
    private var relatedArtworkPrefetchTask: Task<Void, Never>?
    private var fastStartUpgradeTask: Task<Void, Never>?
    private var hlsRenditionPrebuildTask: Task<Void, Never>?
    private var seekWarmupTasks: [String: Task<Void, Never>] = [:]
    private var seekWarmupTaskOrder: [String] = []
    private var recentSeekWarmupKeys = Set<String>()
    private var recentSeekWarmupKeyOrder: [String] = []
    private var filterCancellable: AnyCancellable?
    private var sponsorBlockCancellable: AnyCancellable?
    private var playbackAutoOptimizationCancellable: AnyCancellable?
    private var playbackPerformanceCancellable: AnyCancellable?
    private var sponsorBlockTask: Task<Void, Never>?
    private var danmakuTask: Task<Void, Never>?
    private var danmakuStartupLoadTask: Task<Void, Never>?
    private var danmakuStartupLoadToken: UUID?
    private var danmakuSegmentTasks: [Int: Task<Void, Never>] = [:]
    private var loadedDanmakuSegments = Set<Int>()
    private var loadingDanmakuSegments = Set<Int>()
    private var danmakuSegmentItems: [Int: [DanmakuItem]] = [:]
    private var didFallbackToFullDanmakuLoad = false
    private var lastDanmakuScheduleKey: DanmakuScheduleKey?
    private var isDanmakuUnderPlaybackLoad = false
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var sponsorBlockIdentity: String?
    private var stablePlayerIdentity: String?
    private var stablePlayerErrorCancellable: AnyCancellable?
    private var stablePlayerFirstFrameCancellable: AnyCancellable?
    private var playbackTransitionPlayerViewModel: PlayerStateViewModel? {
        didSet { scheduleRenderStoreSync(.playerIdentity) }
    }
    private var playbackTransitionSnapshot: PlaybackTransitionSnapshot? {
        didSet { scheduleRenderStoreSync(.playerIdentity) }
    }
    private var playbackTransitionFallbackCoverURL: URL? {
        didSet { scheduleRenderStoreSync(.playerIdentity) }
    }
    private var playbackTransitionOpacity = 0.0 {
        didSet { scheduleRenderStoreSync(.playerIdentity) }
    }
    private var playbackTransitionReleaseTask: Task<Void, Never>?
    private var playbackStartupRelease: PlaybackStartupRelease?
    private var playbackStartupWaiters: [UUID: PlaybackStartupWaiter] = [:]
    private var didSelectPlayVariantManually = false
    private var failedPlayVariantIDs = Set<String>()
    private var playbackRecoveryAttemptCount = 0
    private var lastBufferingCDNRefreshCount = 0
    private var bufferingCDNRefreshTask: Task<Void, Never>?
    private var renderStoreSyncTask: Task<Void, Never>?
    private var pendingRenderStoreSyncs: RenderStoreSyncMask = []
    private var didRecordDetailLoadedEvent = false
    private(set) var hasResolvedDetailMetadata = false {
        didSet { scheduleRenderStoreSync(.description) }
    }
    private var isPlaybackInvalidatedForNavigation = false
    private var playVariantSwitchToken: UUID?
    private var uploaderInteractionTask: Task<Void, Never>?
    private var uploaderInteractionLoadIdentity: String?
    private var lastUserSeekAt: Date?
    private var shouldResumePlaybackAfterCancelledNavigation = false
    private var pendingNavigationResumeTime: TimeInterval?
    private var hasPendingNavigationInterruption = false
    private var detailLoadStartTime: CFTimeInterval?
    private var playURLLoadStartTime: CFTimeInterval?
    private var relatedLoadStartTime: CFTimeInterval?
    private let relatedLoadTimeoutNanoseconds: UInt64 = 5_000_000_000
    private static let danmakuSegmentDuration: TimeInterval = 6 * 60
    private static let relatedRecommendationsLimit = 5
    private static let minimumExpandedRelatedCount = relatedRecommendationsLimit
    private static let seekWarmupBucketDuration: TimeInterval = 30
    private static let maxInFlightSeekWarmups = 3
    private static let recentSeekWarmupLimit = 10
    private static let fastStartUpgradeStabilityDelayNanoseconds: UInt64 = 1_250_000_000
    private static let fastStartUpgradeWarmupTimeout: TimeInterval = 1.15
    private static let fastStartUpgradeSeekCooldown: TimeInterval = 1.5
    private static let hlsRenditionPrebuildDelayNanoseconds: UInt64 = 850_000_000
    private static let hlsRenditionPrebuildStepNanoseconds: UInt64 = 360_000_000
    private static let hlsRenditionPrebuildTimeout: TimeInterval = 0.78
    private static let playbackTransitionReleaseDelayNanoseconds: UInt64 = 220_000_000
    private static let playbackTransitionFadeDurationNanoseconds: UInt64 = 280_000_000
    private static let playbackTransitionMaximumRetainNanoseconds: UInt64 = 6_000_000_000
    private static let renderStoreSyncCoalescingDelayNanoseconds: UInt64 = 16_000_000

    private struct SeekWarmupPlan {
        let variants: [PlayVariant]
        let variantLimit: Int
        let pressureReason: String
    }

    private func trackBackgroundTask(_ task: Task<Void, Never>) {
        let id = UUID()
        backgroundTasks[id] = task
        Task(priority: .utility) { [weak self, task] in
            _ = await task.value
            await MainActor.run {
                self?.backgroundTasks[id] = nil
            }
        }
    }

    private func beginPlaybackStartupAttempt() {
        if stablePlayerViewModel?.hasPresentedPlayback == true {
            finishPlaybackStartupWaiters(with: .firstFrame)
        } else {
            playbackStartupRelease = nil
        }
    }

    private func finishPlaybackStartupWaiters(with release: PlaybackStartupRelease?) {
        playbackStartupRelease = release
        guard !playbackStartupWaiters.isEmpty else { return }

        let waiters = playbackStartupWaiters
        playbackStartupWaiters.removeAll()
        for waiter in waiters.values {
            switch release {
            case .firstFrame:
                waiter.continuation.resume(returning: .firstFrame)
            case .failed:
                waiter.continuation.resume(returning: waiter.acceptsFailure ? .failed : nil)
            case .none:
                waiter.continuation.resume(returning: nil)
            }
        }
    }

    private func cancelPlaybackStartupWaiter(_ id: UUID) {
        if let waiter = playbackStartupWaiters.removeValue(forKey: id) {
            waiter.continuation.resume(returning: nil)
        }
    }

    private func clearDetailLoadingTaskIfCurrent(_ token: UUID) {
        guard detailLoadingToken == token else { return }
        detailLoadingTask = nil
        detailLoadingToken = nil
    }

    private func clearCommentsLoadingTaskIfCurrent(_ token: UUID) {
        guard commentsLoadingToken == token else { return }
        commentsLoadingTask = nil
        commentsLoadingToken = nil
    }

    private func clearDanmakuStartupLoadTaskIfCurrent(_ token: UUID) {
        guard danmakuStartupLoadToken == token else { return }
        danmakuStartupLoadTask = nil
        danmakuStartupLoadToken = nil
    }

    private func cancelBackgroundTasks() {
        backgroundTasks.values.forEach { $0.cancel() }
        backgroundTasks.removeAll()
    }

    private var playURLLoadTimeoutNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 3_800_000_000
            : 4_800_000_000
    }

    var hasMoreComments: Bool {
        !commentsEnd
    }

    var shouldShowRelatedSectionShell: Bool {
        state != .idle || playURLState != .idle || relatedState != .idle || !related.isEmpty
    }

    var shouldUseCompactRelatedArtwork: Bool {
        let environment = PlaybackEnvironment.current
        return environment.shouldPreferConservativePlayback
            || playbackAdaptationProfile.shouldThrottleBackgroundPreload
    }

    var shouldShowEmptyCommentsState: Bool {
        guard didCompleteInitialCommentLoad,
              comments.isEmpty,
              commentState == .loaded
        else { return false }
        if let replyCount = detail.stat?.reply {
            return replyCount == 0 && commentsEnd
        }
        return commentsEnd
    }

    var shouldShowCommentReloadPrompt: Bool {
        didCompleteInitialCommentLoad
            && comments.isEmpty
            && commentState == .loaded
            && !shouldShowEmptyCommentsState
    }

    var shouldAutoLoadInlineComments: Bool {
        if !related.isEmpty {
            return true
        }
        switch relatedState {
        case .loaded, .failed:
            return true
        case .idle, .loading:
            return false
        }
    }

    init(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sponsorBlockService: SponsorBlockService
    ) {
        self.detail = seedVideo
        self.selectedCID = seedVideo.cid ?? seedVideo.pages?.first?.cid
        self.api = api
        self.libraryStore = libraryStore
        self.sponsorBlockService = sponsorBlockService
        self.isDanmakuEnabled = libraryStore.danmakuEnabled
        self.danmakuSettings = libraryStore.danmakuSettings
        refreshDetailDisplayMetrics()
        refreshUploaderFanCountText()
        filterCancellable = libraryStore.$blocksGoodsComments
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.refilterLoadedComments()
            }
        sponsorBlockCancellable = libraryStore.$sponsorBlockEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.stablePlayerViewModel?.setSponsorBlockEnabled(isEnabled)
                if isEnabled {
                    self?.scheduleSponsorBlockSegmentsAfterFirstFrame()
                } else {
                    self?.resetSponsorBlockSegments()
                }
        }
        playbackAutoOptimizationCancellable = libraryStore.$playbackAutoOptimizationMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleRenderStoreSync(.danmaku)
            }
        playbackPerformanceCancellable = PlayerPerformanceStore.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRenderStoreSync(.danmaku)
                }
            }
        syncCommentsRenderStore()
        syncRelatedRenderStore()
        syncInteractionRenderStore()
        syncPlaybackRenderStore()
        syncCommentThreadRenderStore()
        syncFavoriteFolderRenderStore()
        syncDanmakuSettingsRenderStore()
        syncDanmakuRenderStore()
        syncNetworkDiagnosticsRenderStore()
        syncDescriptionRenderStore()
        syncPlayerIdentityRenderStore()
    }

    private func syncCommentsRenderStore() {
        commentsRenderStore.update(
            detail: detail,
            comments: comments,
            state: commentState,
            selectedSort: selectedCommentSort,
            didCompleteInitialLoad: didCompleteInitialCommentLoad,
            hasMoreComments: hasMoreComments
        )
    }

    private func syncRelatedRenderStore() {
        relatedRenderStore.update(
            related: related,
            state: relatedState,
            lastLoadTimedOut: lastRelatedLoadTimedOut
        )
    }

    private func scheduleRenderStoreSync(_ syncs: RenderStoreSyncMask) {
        guard !syncs.isEmpty else { return }
        pendingRenderStoreSyncs.formUnion(syncs)
        guard renderStoreSyncTask == nil else { return }
        renderStoreSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.renderStoreSyncCoalescingDelayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.flushScheduledRenderStoreSyncs()
        }
    }

    private func flushScheduledRenderStoreSyncs() {
        let syncs = pendingRenderStoreSyncs
        pendingRenderStoreSyncs = []
        renderStoreSyncTask = nil
        syncRenderStores(syncs)
    }

    private func syncRenderStores(_ syncs: RenderStoreSyncMask) {
        if syncs.contains(.interaction) {
            syncInteractionRenderStore()
        }
        if syncs.contains(.playback) {
            syncPlaybackRenderStore()
        }
        if syncs.contains(.favoriteFolder) {
            syncFavoriteFolderRenderStore()
        }
        if syncs.contains(.danmakuSettings) {
            syncDanmakuSettingsRenderStore()
        }
        if syncs.contains(.networkDiagnostics) {
            syncNetworkDiagnosticsRenderStore()
        }
        if syncs.contains(.description) {
            syncDescriptionRenderStore()
        }
        if syncs.contains(.playerIdentity) {
            syncPlayerIdentityRenderStore()
        }
        if syncs.contains(.danmaku) {
            syncDanmakuRenderStore()
        }
    }

    private func syncInteractionRenderStore() {
        interactionRenderStore.update(
            interactionState: interactionState,
            interactionMessage: interactionMessage,
            isMutatingInteraction: isMutatingInteraction,
            isMutatingLike: isMutatingLike,
            isMutatingCoin: isMutatingCoin,
            isMutatingFavorite: isMutatingFavorite,
            isMutatingFollow: isMutatingFollow,
            playbackFallbackMessage: playbackFallbackMessage
        )
    }

    private func syncPlaybackRenderStore() {
        playbackRenderStore.update(VideoDetailPlaybackRenderSnapshot(viewModel: self))
    }

    private func syncCommentThreadRenderStore() {
        commentThreadRenderStore.update(
            replyThreads: replyThreads,
            replyThreadStates: replyThreadStates,
            replyThreadHasMore: replyThreadHasMore,
            dialogThreads: dialogThreads,
            dialogThreadStates: dialogThreadStates
        )
    }

    private func syncFavoriteFolderRenderStore() {
        favoriteFolderRenderStore.update(
            VideoDetailFavoriteFolderRenderSnapshot(viewModel: self)
        )
    }

    private func syncDanmakuSettingsRenderStore() {
        danmakuSettingsRenderStore.update(
            VideoDetailDanmakuSettingsRenderSnapshot(viewModel: self)
        )
    }

    private func syncDanmakuRenderStore() {
        danmakuRenderStore.update(
            VideoDetailDanmakuRenderSnapshot(viewModel: self)
        )
    }

    private func syncNetworkDiagnosticsRenderStore() {
        networkDiagnosticsRenderStore.update(
            VideoDetailNetworkDiagnosticsRenderSnapshot(viewModel: self)
        )
    }

    private func syncDescriptionRenderStore() {
        descriptionRenderStore.update(
            VideoDetailDescriptionRenderSnapshot(viewModel: self)
        )
    }

    private func syncPlayerIdentityRenderStore() {
        playerIdentityRenderStore.update(
            VideoDetailPlayerIdentityRenderSnapshot(
                playerViewModel: stablePlayerViewModel,
                transitionSnapshot: playbackTransitionSnapshot,
                transitionFallbackCoverURL: playbackTransitionFallbackCoverURL,
                transitionPlayerOpacity: playbackTransitionOpacity
            )
        )
    }

    private func refreshDetailDisplayMetrics() {
        detailDisplayMetrics = VideoDetailDisplayMetrics(video: detail)
    }

    private func refreshUploaderFanCountText() {
        let fanCount = uploaderProfile?.follower ?? uploaderProfile?.card?.fans
        uploaderFanCountText = "粉丝 \(BiliFormatters.compactCount(fanCount))"
    }

    deinit {
        backgroundTasks.values.forEach { $0.cancel() }
        backgroundTasks.removeAll()
        pageLoadingTask?.cancel()
        detailLoadingTask?.cancel()
        detailLoadingToken = nil
        playURLSupplementTask?.cancel()
        playVariantSwitchTask?.cancel()
        commentsLoadingTask?.cancel()
        commentsLoadingToken = nil
        startupPlayURLTask?.cancel()
        fastStartUpgradeTask?.cancel()
        hlsRenditionPrebuildTask?.cancel()
        seekWarmupTasks.values.forEach { $0.cancel() }
        seekWarmupTasks.removeAll()
        seekWarmupTaskOrder.removeAll()
        recentSeekWarmupKeys.removeAll()
        recentSeekWarmupKeyOrder.removeAll()
        bufferingCDNRefreshTask?.cancel()
        renderStoreSyncTask?.cancel()
        let startupWaiters = playbackStartupWaiters
        playbackStartupWaiters.removeAll()
        playbackStartupRelease = nil
        startupWaiters.values.forEach { $0.continuation.resume(returning: nil) }
        relatedLoadingTask?.cancel()
        relatedRefreshTask?.cancel()
        relatedPreloadTask?.cancel()
        relatedArtworkPrefetchTask?.cancel()
        uploaderInteractionTask?.cancel()
        stablePlayerFirstFrameCancellable = nil
        uploaderInteractionLoadIdentity = nil
        sponsorBlockTask?.cancel()
        danmakuTask?.cancel()
        danmakuStartupLoadTask?.cancel()
        danmakuStartupLoadToken = nil
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        Self.cancelMediaWarmupsPreservingCache()
    }

    func load() async {
        discardTerminatedStablePlayerIfNeeded()
        if state == .loading {
            return
        }
        if state == .loaded {
            scheduleDanmakuLoadIfNeeded()
            scheduleRelatedLoadIfNeeded()
            scheduleUploaderAndInteractionLoadIfNeeded()
            if stablePlayerViewModel == nil {
                if selectedPlayVariant?.isPlayable == true {
                    let resumeTime = pendingNavigationResumeTime
                    let shouldResumeOverride: Bool? = shouldResumePlaybackAfterCancelledNavigation
                        ? true
                        : (hasPendingNavigationInterruption ? false : nil)
                    guard !isPlaybackInvalidatedForNavigation else { return }
                    updateStablePlayerViewModelIfNeeded(
                        resumeTimeOverride: resumeTime,
                        shouldResumePlayback: shouldResumeOverride
                    )
                    pendingNavigationResumeTime = nil
                    shouldResumePlaybackAfterCancelledNavigation = false
                    hasPendingNavigationInterruption = false
                } else {
                    await loadPlayURLIfNeeded()
                }
            }
            return
        }
        beginDetailLoadTracking()

        if activateCurrentDetailForFastStart(source: "seed") {
            schedulePlayURLLoadIfNeeded()
            scheduleUploaderAndInteractionLoadIfNeeded()
            scheduleFullDetailLoadIfNeeded(priority: .utility, waitsForFirstFrame: true)
            return
        }

        scheduleDetailAndPlaybackPreloadIfMissingCID(priority: .userInitiated)

        if await applyCachedDetailForFastStartIfAvailable() {
            schedulePlayURLLoadIfNeeded()
            scheduleUploaderAndInteractionLoadIfNeeded()
            scheduleFullDetailLoadIfNeeded(priority: .utility, waitsForFirstFrame: true)
            return
        }

        await loadFullDetailAndMetadata(priority: .userInitiated)
    }

    func cancelBackgroundWork() {
        cancelSupplementalWork()
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
    }

    func suspendPlaybackForNavigation() {
        stablePlayerViewModel?.suspendForNavigation()
    }

    func pausePlaybackForPotentialNavigation() {
        guard !isPlaybackInvalidatedForNavigation, let player = stablePlayerViewModel else { return }
        let resumeTime = currentPlaybackResumeTime()
        if resumeTime > 0.25 {
            pendingNavigationResumeTime = max(pendingNavigationResumeTime ?? 0, resumeTime)
        }
        hasPendingNavigationInterruption = true
        let shouldResume = player.wantsAutoplay
            || player.isPlaying
            || player.playbackSnapshot().isPlaying
        shouldResumePlaybackAfterCancelledNavigation = shouldResumePlaybackAfterCancelledNavigation || shouldResume
        player.suspendForNavigation()
    }

    func resumePlaybackAfterCancelledNavigation() {
        resumePlaybackAfterNavigationInterruptionIfNeeded()
    }

    func resumePlaybackAfterCoveredNavigationIfNeeded() {
        resumePlaybackAfterNavigationInterruptionIfNeeded()
    }

    private func resumePlaybackAfterNavigationInterruptionIfNeeded() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard state == .loaded else { return }
        let shouldResume = shouldResumePlaybackAfterCancelledNavigation
        let resumeTime = pendingNavigationResumeTime
        let shouldResumeOverride: Bool? = shouldResume
            ? true
            : (hasPendingNavigationInterruption ? false : nil)
        discardTerminatedStablePlayerIfNeeded()
        defer {
            shouldResumePlaybackAfterCancelledNavigation = false
            pendingNavigationResumeTime = nil
            hasPendingNavigationInterruption = false
        }
        guard let player = stablePlayerViewModel else {
            if selectedPlayVariant?.isPlayable == true {
                updateStablePlayerViewModelIfNeeded(
                    resumeTimeOverride: resumeTime,
                    shouldResumePlayback: shouldResumeOverride
                )
            } else {
                schedulePlayURLLoadIfNeeded()
            }
            return
        }
        player.restoreAudioAfterCancelledNavigation()
        guard shouldResume else { return }
        player.play()
    }

    func recoverPlaybackAfterAppResume() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        discardTerminatedStablePlayerIfNeeded()
        guard let player = stablePlayerViewModel else {
            if selectedPlayVariant?.isPlayable == true {
                updateStablePlayerViewModelIfNeeded(
                    resumeTimeOverride: pendingNavigationResumeTime ?? currentPlaybackResumeTime(),
                    shouldResumePlayback: true
                )
                pendingNavigationResumeTime = nil
            } else {
                schedulePlayURLLoadIfNeeded()
            }
            return
        }
        let shouldResume = player.wantsAutoplay || player.isPlaying || player.playbackSnapshot().isPlaying
        player.recoverPlaybackAfterAppResume()
        if shouldResume, let message = player.errorMessage, let selectedPlayVariant {
            handlePlaybackError(message, for: selectedPlayVariant)
        }
    }

    func stopPlaybackForNavigation() {
        isPlaybackInvalidatedForNavigation = true
        cancelSupplementalWork()
        Self.cancelMediaWarmupsPreservingCache()
        cancelRelatedLoad()
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        resetDanmakuLoad(clearItems: true)
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        selectedPlayVariant = nil
        if state.isLoading {
            state = .idle
        }
        finishPlaybackStartupWaiters(with: nil)
        playURLState = .idle
        shouldResumePlaybackAfterCancelledNavigation = false
        pendingNavigationResumeTime = nil
        hasPendingNavigationInterruption = false
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        playbackFallbackMessage = nil
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        lastBufferingCDNRefreshCount = 0
        bufferingCDNRefreshTask?.cancel()
        bufferingCDNRefreshTask = nil
        lastUserSeekAt = nil
        resumeDiagnostics = .none
    }

    private nonisolated static func cancelMediaWarmupsPreservingCache() {
        Task(priority: .utility) {
            await VideoPreloadCenter.shared.cancelMediaWarmups(clearCache: false)
        }
    }

    func cancelPlaybackNavigationStop() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        stablePlayerViewModel?.setPlaybackIntent(true)
        stablePlayerViewModel?.recoverPlaybackAfterAppResume()
    }

    @discardableResult
    private func discardTerminatedStablePlayerIfNeeded() -> Bool {
        guard stablePlayerViewModel?.isTerminated == true else { return false }
        finishPlaybackStartupWaiters(with: nil)
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        return true
    }

    private func cancelSupplementalWork() {
        cancelBackgroundTasks()
        pageLoadingTask?.cancel()
        pageLoadingTask = nil
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
        playURLSupplementTask?.cancel()
        playURLSupplementTask = nil
        startupPlayURLTask?.cancel()
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
        fastStartUpgradeTask?.cancel()
        fastStartUpgradeTask = nil
        hlsRenditionPrebuildTask?.cancel()
        hlsRenditionPrebuildTask = nil
        cancelSeekWarmups(clearRecent: true)
        isSupplementingPlayQualities = false
        isSwitchingPlayQuality = false
        pendingPlayVariantID = nil
        playVariantSwitchToken = nil
        relatedPreloadTask?.cancel()
        relatedPreloadTask = nil
        relatedArtworkPrefetchTask?.cancel()
        relatedArtworkPrefetchTask = nil
        relatedRefreshTask?.cancel()
        relatedRefreshTask = nil
        uploaderInteractionTask?.cancel()
        uploaderInteractionTask = nil
        uploaderInteractionLoadIdentity = nil
        finishPlaybackStartupWaiters(with: nil)
    }

    private func cancelRelatedLoad() {
        relatedLoadingTask?.cancel()
        relatedLoadingTask = nil
        relatedRefreshTask?.cancel()
        relatedRefreshTask = nil
        relatedArtworkPrefetchTask?.cancel()
        relatedArtworkPrefetchTask = nil
        if related.isEmpty, relatedState.isLoading {
            relatedState = .idle
        }
    }

    private func beginDetailLoadTracking() {
        if detailLoadStartTime == nil {
            detailLoadStartTime = CACurrentMediaTime()
            detailLoadElapsedMilliseconds = nil
        }
        didRecordDetailLoadedEvent = false
        PlayerMetricsLog.record(.detailLoadStart, metricsID: detail.bvid, title: detail.title)
    }

    private func applyCachedDetailForFastStartIfAvailable() async -> Bool {
        guard !isPlaybackInvalidatedForNavigation else { return false }
        guard let cached = await VideoPreloadCenter.shared.cachedDetail(for: detail.bvid) else {
            return false
        }
        detail = detail.mergingFilledValues(from: cached)
        hasResolvedDetailMetadata = true
        syncCommentsRenderStore()
        selectedCID = selectedCID ?? cached.pages?.first?.cid ?? cached.cid
        return activateCurrentDetailForFastStart(source: "cache")
    }

    @discardableResult
    private func activateCurrentDetailForFastStart(source: String) -> Bool {
        guard !isPlaybackInvalidatedForNavigation else { return false }
        selectedCID = selectedCID ?? detail.pages?.first?.cid ?? detail.cid
        guard canActivateDetailFromCurrentData else { return false }

        warmCachedPlayInfoIfAvailable()
        state = .loaded
        detailLoadElapsedMilliseconds = elapsedMilliseconds(since: detailLoadStartTime) ?? 0
        recordDetailLoadedIfNeeded(source: source)
        scheduleRelatedLoadAfterPlaybackStartIfNeeded()
        return true
    }

    private var canActivateDetailFromCurrentData: Bool {
        !detail.bvid.isEmpty
            && selectedCID != nil
            && !detail.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recordDetailLoadedIfNeeded(source: String) {
        guard !didRecordDetailLoadedEvent else { return }
        didRecordDetailLoadedEvent = true
        PlayerMetricsLog.record(
            .detailLoaded,
            metricsID: detail.bvid,
            title: detail.title,
            message: source
        )
    }

    private func scheduleFullDetailLoadIfNeeded(
        priority: TaskPriority = .utility,
        waitsForFirstFrame: Bool = false
    ) {
        guard !isPlaybackInvalidatedForNavigation, detailLoadingTask == nil else { return }
        let token = UUID()
        detailLoadingToken = token
        detailLoadingTask = Task(priority: priority) { [weak self] in
            guard let self else { return }
            defer {
                self.clearDetailLoadingTaskIfCurrent(token)
            }
            if waitsForFirstFrame {
                guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: true),
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation
                else { return }
                if case .firstFrame = release {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                }
            }
            await self.loadFullDetailAndMetadata(priority: priority)
        }
    }

    private func scheduleDetailAndPlaybackPreloadIfMissingCID(priority: TaskPriority = .utility) {
        guard selectedCID == nil, !detail.bvid.isEmpty else { return }
        let seedDetail = detail
        let preferredQuality = adaptiveStartupPreferredQuality
        let targetPreferredQuality = targetPlaybackPreferredQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let adaptationProfile = playbackAdaptationProfile
        trackBackgroundTask(
            Task(priority: priority) { [api] in
                await VideoPreloadCenter.shared.prioritizePlayback(for: seedDetail)
                await VideoPreloadCenter.shared.preloadDetailAndPlayback(
                    seedDetail,
                    api: api,
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: targetPreferredQuality,
                    cdnPreference: cdnPreference,
                    warmsMedia: true,
                    mediaWarmupDelay: 0.15,
                    priority: priority,
                    playbackAdaptationProfile: adaptationProfile
                )
            }
        )
    }

    private func schedulePlayURLLoadIfNeeded() {
        guard !isPlaybackInvalidatedForNavigation,
              selectedPlayVariant == nil,
              !playURLState.isLoading
        else { return }
        trackBackgroundTask(
            Task(priority: .userInitiated) { [weak self] in
                await self?.loadPlayURLIfNeeded()
            }
        )
    }

    private func resumeDurationHint(for cid: Int?) -> TimeInterval? {
        if let cid,
           let pageDuration = detail.pages?.first(where: { $0.cid == cid })?.duration,
           pageDuration > 0 {
            return TimeInterval(pageDuration)
        }
        return detail.duration.map(TimeInterval.init)
    }

    private func scheduleUploaderAndInteractionLoadIfNeeded() {
        guard !isPlaybackInvalidatedForNavigation, uploaderInteractionTask == nil else { return }
        guard let identity = currentUploaderInteractionIdentity,
              uploaderInteractionLoadIdentity != identity,
              (uploaderProfile == nil || interactionState == VideoInteractionState())
        else { return }
        uploaderInteractionLoadIdentity = identity
        uploaderInteractionTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.uploaderInteractionTask = nil
            }
            let didLoad = await self.loadUploaderAndInteractionAfterFirstFrame()
            if !didLoad {
                self.uploaderInteractionLoadIdentity = nil
            }
        }
    }

    private var currentUploaderInteractionIdentity: String? {
        let mid = detail.owner?.mid ?? 0
        let aid = detail.aid ?? 0
        guard mid > 0 || aid > 0 else { return nil }
        return "\(mid)-\(aid)"
    }

    private func loadFullDetailAndMetadata(priority: TaskPriority = .userInitiated) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailDetailLoad",
            message: "bvid=\(detail.bvid) priority=\(String(describing: priority))"
        )
        var signpostMessage = "bvid=\(detail.bvid) loading"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailDetailLoad",
                signpostState,
                message: signpostMessage
            )
        }
        let isCurrentDetailTask = detailLoadingTask != nil
        if state != .loaded {
            state = .loading
            if detailLoadStartTime == nil {
                detailLoadStartTime = CACurrentMediaTime()
                detailLoadElapsedMilliseconds = nil
            }
        }
        do {
            let fullDetail = try await PlayerMetricsLog.withSignpostedInterval(
                "VideoDetailDetailFetch",
                message: "bvid=\(detail.bvid) priority=\(String(describing: priority))"
            ) {
                try await VideoPreloadCenter.shared.detail(
                    for: detail.bvid,
                    api: api,
                    priority: priority
                )
            }
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else {
                signpostMessage = "bvid=\(detail.bvid) cancelled"
                return
            }
            detail = detail.mergingFilledValues(from: fullDetail)
            hasResolvedDetailMetadata = true
            syncCommentsRenderStore()
            selectedCID = selectedCID ?? fullDetail.pages?.first?.cid ?? fullDetail.cid
            if !activateCurrentDetailForFastStart(source: "network") {
                state = .loaded
                detailLoadElapsedMilliseconds = elapsedMilliseconds(since: detailLoadStartTime) ?? 0
                recordDetailLoadedIfNeeded(source: "network")
                scheduleRelatedLoadIfNeeded()
            }
            schedulePlayURLLoadIfNeeded()
            scheduleUploaderAndInteractionLoadIfNeeded()
            if isCurrentDetailTask {
                detailLoadingTask = nil
            }
            signpostMessage = "bvid=\(detail.bvid) loaded"
        } catch {
            guard !Task.isCancelled else {
                signpostMessage = "bvid=\(detail.bvid) cancelled"
                return
            }
            guard !isPlaybackInvalidatedForNavigation else {
                signpostMessage = "bvid=\(detail.bvid) invalidated"
                return
            }
            if isCurrentDetailTask {
                detailLoadingTask = nil
            }
            detailLoadElapsedMilliseconds = elapsedMilliseconds(since: detailLoadStartTime)
            if state != .loaded {
                state = .failed(error.localizedDescription)
            }
            hasResolvedDetailMetadata = true
            signpostMessage = "bvid=\(detail.bvid) failed \(error.localizedDescription)"
        }
    }

    func selectPage(_ page: VideoPage) {
        isPlaybackInvalidatedForNavigation = false
        cancelBackgroundTasks()
        selectedCID = page.cid
        resetDanmakuLoad(clearItems: true)
        playVariants = []
        selectedPlayVariant = nil
        playURLElapsedMilliseconds = nil
        lastPlayURLSource = nil
        didSelectPlayVariantManually = false
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        lastBufferingCDNRefreshCount = 0
        bufferingCDNRefreshTask?.cancel()
        bufferingCDNRefreshTask = nil
        finishPlaybackStartupWaiters(with: nil)
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        playbackFallbackMessage = nil
        playURLSupplementTask?.cancel()
        playURLSupplementTask = nil
        playVariantSwitchTask?.cancel()
        playVariantSwitchTask = nil
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        startupPlayURLTask?.cancel()
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
        fastStartUpgradeTask?.cancel()
        fastStartUpgradeTask = nil
        hlsRenditionPrebuildTask?.cancel()
        hlsRenditionPrebuildTask = nil
        isSupplementingPlayQualities = false
        isSwitchingPlayQuality = false
        pendingPlayVariantID = nil
        playVariantSwitchToken = nil
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        playURLState = .idle
        pageLoadingTask?.cancel()
        pageLoadingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadPlayURL()
        }
    }

    func loadMoreCommentsIfNeeded(current comment: Comment?) async {
        guard let comment, comments.last?.id == comment.id, !commentState.isLoading, !commentsEnd else { return }
        await loadCommentsPage()
    }

    func loadMoreComments() async {
        guard !commentState.isLoading, !commentsEnd else { return }
        await loadCommentsPage()
    }

    func retryComments() async {
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        await loadInitialComments()
    }

    func retryRelated() async {
        relatedLoadingTask?.cancel()
        relatedLoadingTask = nil
        relatedRefreshTask?.cancel()
        relatedRefreshTask = nil
        related = []
        relatedState = .idle
        lastRelatedLoadTimedOut = false
        await loadRelated(forceRefresh: true)
    }

    func replies(for comment: Comment) -> [Comment] {
        replyThreads[comment.id] ?? comment.replies ?? []
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = replyThreadHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        replyThreadStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard replyThreads[comment.id] == nil else { return }
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func reloadReplies(for comment: Comment) async {
        replyThreads[comment.id] = nil
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard replyThreadHasMore[comment.id] != false,
              !(replyThreadStates[comment.id]?.isLoading ?? false) else { return }
        await loadReplyPage(for: comment, reset: false)
    }

    func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = dialogKey(root: root, reply: reply)
        return dialogThreads[key] ?? localDialogReplies(root: root, reply: reply)
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        dialogThreadStates[dialogKey(root: root, reply: reply)] ?? .idle
    }

    func loadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard dialogThreads[key] == nil else { return }
        await loadDialogPage(for: root, reply: reply)
    }

    func reloadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        dialogThreads[key] = nil
        await loadDialogPage(for: root, reply: reply)
    }

    func selectCommentSort(_ sort: CommentSort) async {
        guard selectedCommentSort != sort else { return }
        selectedCommentSort = sort
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        await loadInitialComments()
    }

    func loadInitialCommentsIfNeeded() async {
        guard comments.isEmpty, !commentState.isLoading else { return }
        await loadInitialComments()
    }

    func beginInitialCommentsLoadIfNeeded(waitForPlaybackStart: Bool = true) {
        guard detail.aid != nil else {
            if comments.isEmpty, !commentState.isLoading {
                commentState = .idle
            }
            return
        }
        if commentState.isLoading, commentsLoadingTask == nil {
            commentState = comments.isEmpty ? .idle : .loaded
        }
        guard comments.isEmpty, !commentState.isLoading else { return }
        commentsLoadingTask?.cancel()
        let token = UUID()
        commentsLoadingToken = token
        commentsLoadingTask = Task(priority: waitForPlaybackStart ? .utility : .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearCommentsLoadingTaskIfCurrent(token)
            }
            if waitForPlaybackStart {
                guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: true),
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation
                else { return }
                if case .firstFrame = release {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                }
            }
            await self.loadInitialComments()
        }
    }

    func retryPlayURL() async {
        isPlaybackInvalidatedForNavigation = false
        await loadPlayURL()
    }

    func toggleDanmaku() {
        isDanmakuEnabled.toggle()
        libraryStore.setDanmakuEnabled(isDanmakuEnabled)
        if isDanmakuEnabled, danmakuItems.isEmpty {
            scheduleDanmakuLoadIfNeeded()
        } else if !isDanmakuEnabled {
            resetDanmakuLoad(clearItems: false)
        }
    }

    func updateDanmakuSettings(_ settings: DanmakuSettings) {
        let normalizedSettings = settings.normalized
        danmakuSettings = normalizedSettings
        libraryStore.setDanmakuSettings(normalizedSettings)
    }

    func prepareForUserSeek(toProgress progress: Double) {
        guard !isPlaybackInvalidatedForNavigation,
              let variant = selectedPlayVariant,
              variant.isPlayable,
              let cid = selectedCID
        else { return }
        let duration = stablePlayerViewModel?.displayDuration
            ?? resumeDurationHint(for: cid)
            ?? detail.duration.map(TimeInterval.init)
        guard let duration, duration > 0 else { return }

        let targetTime = min(max(progress, 0), 1) * duration
        lastUserSeekAt = Date()
        let targetSegment = danmakuSegmentIndex(for: targetTime)
        let targetScheduleKey = danmakuScheduleKey(cid: cid, playbackTime: targetTime, segmentIndex: targetSegment)
        if lastDanmakuScheduleKey != targetScheduleKey {
            resetDanmakuLoad(clearItems: true)
        }
        isDanmakuUnderPlaybackLoad = true
        scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: cid, around: targetTime, force: false)

        let bvid = detail.bvid
        let page = selectedPageNumber
        let warmupPlan = seekWarmupPlan(primary: variant)
        let warmupVariants = warmupPlan.variants
        let warmupKey = seekWarmupKey(
            bvid: bvid,
            cid: cid,
            page: page,
            variants: warmupVariants,
            playbackTime: targetTime
        )
        guard shouldScheduleSeekWarmup(for: warmupKey) else { return }

        let task = Task(priority: .userInitiated) { [weak self, warmupVariants, warmupPlan] in
            let didWarm = await VideoPreloadCenter.shared.warmVariantsAroundSeek(
                warmupVariants,
                bvid: bvid,
                cid: cid,
                page: page,
                playbackTime: targetTime
            )
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                PlayerMetricsLog.record(
                    .seek,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "warm target=\(String(format: "%.2fs", targetTime)) q=\(Self.hlsQualitySummary(warmupVariants.map(\.quality))) limit=\(warmupPlan.variantLimit) profile=\(self.playbackAdaptationProfile.diagnosticTitle) reason=\(warmupPlan.pressureReason) \(didWarm ? "hit" : "timeout")"
                )
                self.finishSeekWarmup(for: warmupKey, didWarm: didWarm)
            }
        }
        seekWarmupTasks[warmupKey] = task
        seekWarmupTaskOrder.append(warmupKey)
    }

    private func seekWarmupPlan(primary variant: PlayVariant) -> SeekWarmupPlan {
        let pressureReason = seekWarmupPressureReason(primary: variant)
        let variantLimit = seekWarmupVariantLimit(pressureReason: pressureReason)
        let variants = seekWarmupVariants(
            primary: variant,
            pressureReason: pressureReason,
            variantLimit: variantLimit
        )
        return SeekWarmupPlan(
            variants: variants,
            variantLimit: variantLimit,
            pressureReason: pressureReason ?? "normal"
        )
    }

    private func seekWarmupVariants(
        primary variant: PlayVariant,
        pressureReason: String?,
        variantLimit: Int
    ) -> [PlayVariant] {
        var result = [PlayVariant]()
        var seen = Set<String>()

        func append(_ candidate: PlayVariant?) {
            guard let candidate,
                  candidate.isPlayable,
                  candidate.videoURL != nil,
                  candidate.dynamicRange != .dolbyVision,
                  candidate.videoStream?.isHardwareDecodingCompatibleVideo == true,
                  seen.insert(candidate.id).inserted
            else { return }
            result.append(candidate)
        }

        append(variant)
        guard variantLimit > 1,
              variant.audioURL != nil
        else { return result }
        let preferred = preferredDefaultVariant(in: playVariants)
        let audioMatchedPreferred = preferred?.audioURL == variant.audioURL ? preferred : nil
        append(audioMatchedPreferred)
        if result.count < variantLimit {
            append(seekWarmupFallbackVariant(
                primary: variant,
                preferred: audioMatchedPreferred,
                pressureReason: pressureReason
            ))
        }
        return Array(result.prefix(variantLimit))
    }

    private func seekWarmupVariantLimit(pressureReason: String?) -> Int {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return 1 }
        switch environment.networkClass {
        case .wifi:
            return pressureReason == nil ? 2 : 3
        case .unknown:
            return pressureReason == nil ? 1 : 2
        case .cellular, .constrained:
            return 1
        }
    }

    private func seekWarmupPressureReason(primary variant: PlayVariant) -> String? {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return nil }
        let profile = playbackAdaptationProfile
        guard profile.isEnabled else { return nil }

        if let session = PlayerPerformanceStore.shared.session(for: detail.bvid) {
            if (session.accessLogStallCount ?? 0) > 0 {
                return "accesslog-stall"
            }
            if session.seekRecoverySlowCount > 0
                || session.lastSeekRecoveryMilliseconds.map({ $0 >= 1_250 }) == true {
                return "seek-recovery"
            }
            if session.bufferCount > 0 {
                return "buffering"
            }
            if let observedKbps = session.observedBitrateKilobitsPerSecond,
               observedKbps > 0,
               let bandwidth = variant.bandwidth,
               bandwidth > 0 {
                let requiredKbps = max(Int((Double(bandwidth) / 1_000) * 1.15), 1)
                if observedKbps < requiredKbps {
                    return "low-throughput"
                }
            }
        }

        switch profile.level {
        case .normal, .fallback:
            return nil
        case .cautious:
            return "history-cautious"
        case .slow:
            return "history-slow"
        }
    }

    private func seekWarmupFallbackVariant(
        primary variant: PlayVariant,
        preferred: PlayVariant?,
        pressureReason: String?
    ) -> PlayVariant? {
        guard pressureReason != nil else { return nil }
        let referenceQuality = min(variant.quality, preferred?.quality ?? variant.quality)
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != variant.id
                    && $0.id != preferred?.id
                    && $0.audioURL == variant.audioURL
                    && $0.quality < referenceQuality
                    && $0.dynamicRange != .dolbyVision
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
                    && $0.videoURL != nil
            }
        return candidates.first(where: { !$0.isProgressiveFastStart })
            ?? candidates.first
    }

    private func shouldScheduleSeekWarmup(for key: String) -> Bool {
        guard !recentSeekWarmupKeys.contains(key), seekWarmupTasks[key] == nil else {
            return false
        }
        while seekWarmupTaskOrder.count >= Self.maxInFlightSeekWarmups,
              let evictedKey = seekWarmupTaskOrder.first {
            seekWarmupTaskOrder.removeFirst()
            seekWarmupTasks[evictedKey]?.cancel()
            seekWarmupTasks[evictedKey] = nil
        }
        return true
    }

    private func finishSeekWarmup(for key: String, didWarm: Bool) {
        seekWarmupTasks[key] = nil
        seekWarmupTaskOrder.removeAll { $0 == key }
        guard didWarm else { return }
        rememberRecentSeekWarmup(key)
    }

    private func rememberRecentSeekWarmup(_ key: String) {
        recentSeekWarmupKeys.insert(key)
        recentSeekWarmupKeyOrder.removeAll { $0 == key }
        recentSeekWarmupKeyOrder.append(key)
        while recentSeekWarmupKeyOrder.count > Self.recentSeekWarmupLimit {
            let evictedKey = recentSeekWarmupKeyOrder.removeFirst()
            recentSeekWarmupKeys.remove(evictedKey)
        }
    }

    private func cancelSeekWarmups(clearRecent: Bool = false) {
        seekWarmupTasks.values.forEach { $0.cancel() }
        seekWarmupTasks.removeAll()
        seekWarmupTaskOrder.removeAll()
        if clearRecent {
            recentSeekWarmupKeys.removeAll()
            recentSeekWarmupKeyOrder.removeAll()
        }
    }

    private func seekWarmupKey(
        bvid: String,
        cid: Int,
        page: Int?,
        variants: [PlayVariant],
        playbackTime: TimeInterval
    ) -> String {
        let bucket = Int(max(playbackTime, 0) / Self.seekWarmupBucketDuration)
        return [
            bvid,
            String(cid),
            String(page ?? 0),
            variants.map(\.id).joined(separator: "+"),
            String(bucket)
        ].joined(separator: "|")
    }

    var effectiveDanmakuSettings: DanmakuSettings {
        var settings = danmakuSettings
        settings.loadFactor = libraryStore.isPlaybackAutoOptimizationEnabled
            ? playbackAdaptationProfile.danmakuLoadFactor
            : 1.0
        return settings.normalized
    }

    func selectPlayVariant(_ variant: PlayVariant) {
        guard !isPlaybackInvalidatedForNavigation, variant.isPlayable else { return }
        guard selectedPlayVariant?.id != variant.id else { return }
        let initialResumeTime = currentPlaybackResumeTime()
        let initialShouldResumePlayback = currentPlaybackIntent()
        let initialPlaybackRate = stablePlayerViewModel?.playbackRate ?? .x10
        let cid = selectedCID
        let token = UUID()
        didSelectPlayVariantManually = true
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        lastBufferingCDNRefreshCount = 0
        libraryStore.setPreferredVideoQuality(variant.quality)
        fastStartUpgradeTask?.cancel()
        fastStartUpgradeTask = nil
        playVariantSwitchTask?.cancel()
        playVariantSwitchTask = nil
        playVariantSwitchToken = nil
        isSwitchingPlayQuality = false
        pendingPlayVariantID = nil
        Task { [quality = variant.quality, cdnPreference = libraryStore.effectivePlaybackCDNPreference] in
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: quality,
                targetPreferredQuality: quality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: PlayerPlaybackAdaptationProfile(level: .normal)
            )
        }
        if switchPlayVariantInPlaceIfPossible(variant) {
            return
        }
        playVariantSwitchToken = token
        isSwitchingPlayQuality = true
        pendingPlayVariantID = variant.id
        playVariantSwitchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await VideoPreloadCenter.shared.warmVariantAndWait(
                variant,
                bvid: self.detail.bvid,
                timeout: 1.15
            )
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.playVariantSwitchToken == token
            else { return }

            let resumeTime = max(initialResumeTime, self.currentPlaybackResumeTime())
            let shouldResumePlayback = initialShouldResumePlayback || self.currentPlaybackIntent()
            let playbackRate = self.stablePlayerViewModel?.playbackRate ?? initialPlaybackRate
            self.selectedPlayVariant = variant
            self.playbackFallbackMessage = nil
            self.updateStablePlayerViewModelIfNeeded(
                resumeTimeOverride: resumeTime,
                shouldResumePlayback: shouldResumePlayback,
                playbackRateOverride: playbackRate
            )
            self.clearPlayVariantSwitchIfCurrent(token)
        }
    }

    private func switchPlayVariantInPlaceIfPossible(_ variant: PlayVariant) -> Bool {
        guard let playerViewModel = stablePlayerViewModel,
              playerViewModel.engineDiagnostics.hlsVideoVariantCount > 1,
              playerViewModel.preferVideoRenditionInCurrentItem(variant)
        else { return false }

        selectedPlayVariant = variant
        stablePlayerIdentity = playerIdentity(for: variant)
        playbackFallbackMessage = nil
        observePlaybackErrors(playerViewModel, variant: variant)
        logSelectedPlayVariant(
            variant,
            availableVariants: playVariants,
            source: "manualInPlaceQuality"
        )
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "manualInPlaceQuality q\(variant.quality)"
        )
        return true
    }

    @discardableResult
    func toggleLike() async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法点赞"
            return false
        }
        let targetState = !interactionState.isLiked
        return await performInteractionMutation(.like) {
            do {
                try await api.toggleVideoLike(aid: aid, liked: targetState)
                interactionState.isLiked = targetState
            } catch {
                guard recoverLikeStateMismatchIfNeeded(error, targetState: targetState) else {
                    throw error
                }
            }
        }
    }

    @discardableResult
    func addCoin() async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法投币"
            return false
        }
        guard interactionState.coinCount < 2 else {
            interactionMessage = "这个视频已经投过 2 枚币了"
            return false
        }
        return await performInteractionMutation(.coin) {
            try await api.addVideoCoin(aid: aid, selectLike: interactionState.isLiked)
            interactionState.coinCount += 1
        }
    }

    @discardableResult
    func toggleFavorite() async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法收藏"
            return false
        }
        let targetState = !interactionState.isFavorited
        return await performInteractionMutation(.favorite) {
            try await api.setVideoFavorite(aid: aid, favorited: targetState)
            interactionState.isFavorited = targetState
        }
    }

    func loadFavoriteFoldersForCurrentVideo(forceRefresh: Bool = false) async {
        guard let aid = detail.aid else {
            favoriteFolders = []
            favoriteFolderState = .failed("没有找到视频 AV 号，无法读取收藏夹")
            return
        }
        guard forceRefresh || favoriteFolders.isEmpty else { return }
        favoriteFolderState = .loading
        do {
            favoriteFolders = try await api.fetchFavoriteFolders(for: aid)
            favoriteFolderState = .loaded
            interactionState.isFavorited = favoriteFolders.contains { $0.isFavorited }
            interactionMessage = nil
        } catch BiliAPIError.missingSESSDATA {
            favoriteFolders = []
            favoriteFolderState = .failed("请先登录后再查看收藏夹")
        } catch {
            favoriteFolders = []
            favoriteFolderState = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func setFavoriteFolders(selectedIDs: Set<Int>) async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法收藏"
            return false
        }
        let currentIDs = Set(favoriteFolders.filter(\.isFavorited).map(\.id))
        let addIDs = selectedIDs.subtracting(currentIDs)
        let removeIDs = currentIDs.subtracting(selectedIDs)
        guard !addIDs.isEmpty || !removeIDs.isEmpty else {
            interactionMessage = selectedIDs.isEmpty ? "未选择收藏夹" : "收藏夹未变化"
            return true
        }

        return await performInteractionMutation(.favorite) {
            try await api.setVideoFavorite(
                aid: aid,
                addFolderIDs: addIDs,
                removeFolderIDs: removeIDs
            )
            interactionState.isFavorited = !selectedIDs.isEmpty
            favoriteFolders = try await api.fetchFavoriteFolders(for: aid)
            favoriteFolderState = .loaded
            interactionMessage = selectedIDs.isEmpty ? "已取消收藏" : "已更新收藏夹"
        }
    }

    @discardableResult
    func toggleFollow() async -> Bool {
        guard let mid = detail.owner?.mid, mid > 0 else {
            interactionMessage = "没有找到 UP 主 UID，无法关注"
            return false
        }
        let targetState = !interactionState.isFollowing
        return await performInteractionMutation(.follow) {
            try await api.setUploaderFollowing(mid: mid, following: targetState)
            interactionState.isFollowing = targetState
        }
    }

    private func loadUploaderAndInteraction() async {
        async let uploader: Void = loadUploaderProfile()
        async let interaction: Void = loadInteractionState()
        _ = await (uploader, interaction)
    }

    private func loadUploaderAndInteractionAfterFirstFrame() async -> Bool {
        guard let release = await waitForPlaybackStartupRelease(acceptsFailure: true),
              !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation
        else { return false }
        if case .firstFrame = release {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return false }
        }
        await loadUploaderAndInteraction()
        return true
    }

    private func loadPlayURLIfNeeded() async {
        guard !isPlaybackInvalidatedForNavigation, selectedPlayVariant == nil, !playURLState.isLoading else { return }
        await loadPlayURL()
    }

    private func loadPlayURL(mode: PlayURLLoadMode = .normal) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailPlayURL",
            message: "bvid=\(detail.bvid) cid=\(selectedCID ?? 0) mode=\(mode)"
        )
        var signpostMessage = "bvid=\(detail.bvid) loading"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailPlayURL",
                signpostState,
                message: signpostMessage
            )
        }
        playURLState = .loading
        playURLLoadStartTime = CACurrentMediaTime()
        playURLElapsedMilliseconds = nil
        lastPlayURLSource = nil
        playURLSupplementTask?.cancel()
        playURLSupplementTask = nil
        fastStartUpgradeTask?.cancel()
        fastStartUpgradeTask = nil
        isSupplementingPlayQualities = false
        if mode == .playbackRecovery {
            cancelStartupPlayURLTask()
        }
        PlayerMetricsLog.record(.playURLStart, metricsID: detail.bvid, title: detail.title, message: mode.startMessage)
        guard let cid = selectedCID else {
            playVariants = []
            selectedPlayVariant = nil
            playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
            playURLState = .failed("没有找到视频 CID，无法请求播放地址")
            signpostMessage = "bvid=\(detail.bvid) missing cid"
            return
        }
        let pageNumber = selectedPageNumber
        var deferredPlayableFallback: (data: PlayURLData, source: String)?
        func rememberDeferredPlayableFallback(_ data: PlayURLData, source: String) {
            guard mode.allowsNetworkFailureCacheFallback else { return }
            guard isPlayablePlayURLData(data) else { return }
            if let existing = deferredPlayableFallback,
               existing.data.highestPlayableQuality >= data.highestPlayableQuality {
                return
            }
            deferredPlayableFallback = (data, source)
        }

        do {
            scheduleAutomaticCDNRecommendationForPlayback()
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: adaptiveStartupPreferredQuality,
                targetPreferredQuality: targetPlaybackPreferredQuality,
                cdnPreference: libraryStore.effectivePlaybackCDNPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            if mode.allowsStartupCache,
               let cachedPlayableData = await VideoPreloadCenter.shared.cachedPlayablePlayURL(
                for: detail.bvid,
                cid: cid,
                page: pageNumber,
                preferredQuality: adaptiveStartupPreferredQuality
            ) {
                guard !isPlaybackInvalidatedForNavigation else {
                    signpostMessage = "bvid=\(detail.bvid) invalidated"
                    return
                }
                let needsStartupRefetch = shouldRefetchForStartupQuality(cachedPlayableData)
                if needsStartupRefetch {
                    rememberDeferredPlayableFallback(cachedPlayableData, source: "playableCacheFallbackAfterNetworkFailure")
                    PlayerMetricsLog.logger.info(
                        "playURLPlayableCacheBypass bvid=\(self.detail.bvid, privacy: .public) startupPreferred=\(self.adaptiveStartupPreferredQuality ?? 0, privacy: .public) targetPreferred=\(self.targetPlaybackPreferredQuality ?? 0, privacy: .public) cachedQualities=\(Self.qualitySummary(cachedPlayableData.playVariants), privacy: .public)"
                    )
                } else {
                    let source = shouldRefetchForPreferredQuality(cachedPlayableData) ? "playableCacheTargetMiss" : "playableCache"
                    PlayerMetricsLog.record(
                        .playURLLoaded,
                        metricsID: detail.bvid,
                        title: detail.title,
                        message: playURLLoadedMessage(source: source, data: cachedPlayableData)
                    )
                    await applyPlayURLData(
                        cachedPlayableData,
                        cid: cid,
                        page: pageNumber,
                        source: source
                    )
                    signpostMessage = "bvid=\(detail.bvid) playable cache"
                    return
                }
            }
            if mode.allowsStartupCache,
               let cachedData = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                for: detail.bvid,
                cid: cid,
                page: pageNumber,
                waitsForPending: false,
                preferredQuality: adaptiveStartupPreferredQuality
            ) {
                guard !isPlaybackInvalidatedForNavigation else {
                    signpostMessage = "bvid=\(detail.bvid) invalidated"
                    return
                }
                let needsStartupRefetch = shouldRefetchForStartupQuality(cachedData)
                if !needsStartupRefetch {
                    let source = shouldRefetchForPreferredQuality(cachedData) ? "cacheTargetMiss" : "cache"
                    PlayerMetricsLog.record(
                        .playURLLoaded,
                        metricsID: detail.bvid,
                        title: detail.title,
                        message: playURLLoadedMessage(source: source, data: cachedData)
                    )
                    await applyPlayURLData(
                        cachedData,
                        cid: cid,
                        page: pageNumber,
                        source: source
                    )
                    signpostMessage = "bvid=\(detail.bvid) cached"
                    return
                }
                rememberDeferredPlayableFallback(cachedData, source: "cacheFallbackAfterNetworkFailure")
                PlayerMetricsLog.logger.info(
                    "playURLCacheBypass bvid=\(self.detail.bvid, privacy: .public) startupPreferred=\(self.adaptiveStartupPreferredQuality ?? 0, privacy: .public) targetPreferred=\(self.targetPlaybackPreferredQuality ?? 0, privacy: .public) cachedQualities=\(Self.qualitySummary(cachedData.playVariants), privacy: .public)"
                )
            }
            if mode.allowsStartupCache,
               let pendingData = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                for: detail.bvid,
                cid: cid,
                page: pageNumber,
                waitsForPending: true,
                preferredQuality: adaptiveStartupPreferredQuality,
                maximumPendingWait: PlaybackEnvironment.current.preferredPlayURLStartupGrace
            ) {
                guard !isPlaybackInvalidatedForNavigation else {
                    signpostMessage = "bvid=\(detail.bvid) invalidated"
                    return
                }
                let needsStartupRefetch = shouldRefetchForStartupQuality(pendingData)
                if needsStartupRefetch {
                    rememberDeferredPlayableFallback(pendingData, source: "pendingCacheFallbackAfterNetworkFailure")
                    PlayerMetricsLog.logger.info(
                        "playURLPendingCacheBypass bvid=\(self.detail.bvid, privacy: .public) startupPreferred=\(self.adaptiveStartupPreferredQuality ?? 0, privacy: .public) targetPreferred=\(self.targetPlaybackPreferredQuality ?? 0, privacy: .public) cachedQualities=\(Self.qualitySummary(pendingData.playVariants), privacy: .public)"
                    )
                } else {
                    let source = shouldRefetchForPreferredQuality(pendingData) ? "pendingCacheTargetMiss" : "pendingCache"
                    PlayerMetricsLog.record(
                        .playURLLoaded,
                        metricsID: detail.bvid,
                        title: detail.title,
                        message: playURLLoadedMessage(source: source, data: pendingData)
                    )
                    await applyPlayURLData(
                        pendingData,
                        cid: cid,
                        page: pageNumber,
                        source: source
                    )
                    signpostMessage = "bvid=\(detail.bvid) pending cache"
                    return
                }
            }
            let data = try await startupPlayURLForDefaultQuality(
                bvid: detail.bvid,
                cid: cid,
                page: pageNumber
            )
            guard isPlayablePlayURLData(data) else {
                throw BiliAPIError.emptyPlayURL
            }
            guard !Task.isCancelled else {
                signpostMessage = "bvid=\(detail.bvid) cancelled"
                return
            }
            await VideoPreloadCenter.shared.store(
                data,
                bvid: detail.bvid,
                cid: cid,
                page: pageNumber,
                preferredQuality: adaptiveStartupPreferredQuality,
                targetPreferredQuality: targetPlaybackPreferredQuality,
                cdnPreference: libraryStore.effectivePlaybackCDNPreference,
                warmsMedia: false,
                mediaWarmupDelay: 0
            )
            guard !isPlaybackInvalidatedForNavigation else {
                signpostMessage = "bvid=\(detail.bvid) invalidated"
                return
            }
            PlayerMetricsLog.record(
                .playURLLoaded,
                metricsID: detail.bvid,
                title: detail.title,
                message: playURLLoadedMessage(source: "network", data: data)
            )
            await applyPlayURLData(data, cid: cid, page: pageNumber, source: "network")
            signpostMessage = "bvid=\(detail.bvid) network"
        } catch {
            guard !Task.isCancelled else {
                signpostMessage = "bvid=\(detail.bvid) cancelled"
                return
            }
            guard !isPlaybackInvalidatedForNavigation else {
                signpostMessage = "bvid=\(detail.bvid) invalidated"
                return
            }
            if mode.allowsNetworkFailureCacheFallback, let fallback = deferredPlayableFallback {
                PlayerMetricsLog.record(
                    .playURLLoaded,
                    metricsID: detail.bvid,
                    title: detail.title,
                    message: playURLLoadedMessage(
                        source: fallback.source,
                        data: fallback.data,
                        note: "networkFailureDeferredCache",
                        error: error
                    )
                )
                await applyPlayURLData(
                    fallback.data,
                    cid: cid,
                    page: pageNumber,
                    source: fallback.source
                )
                signpostMessage = "bvid=\(detail.bvid) deferred cache after failure"
                return
            }
            if mode.allowsNetworkFailureCacheFallback,
               let staleFallback = await VideoPreloadCenter.shared.cachedPlayablePlayURL(
                for: detail.bvid,
                cid: cid,
                page: pageNumber,
                preferredQuality: nil
            ), isPlayablePlayURLData(staleFallback) {
                PlayerMetricsLog.record(
                    .playURLLoaded,
                    metricsID: detail.bvid,
                    title: detail.title,
                    message: playURLLoadedMessage(
                        source: "stalePlayableCacheAfterNetworkFailure",
                        data: staleFallback,
                        note: "networkFailureStaleCache",
                        error: error
                    )
                )
                await applyPlayURLData(
                    staleFallback,
                    cid: cid,
                    page: pageNumber,
                    source: "stalePlayableCacheAfterNetworkFailure"
                )
                playbackFallbackMessage = "播放地址接口临时失败，已使用上次可播放线路"
                signpostMessage = "bvid=\(detail.bvid) stale playable cache after failure"
                return
            }
            if mode.allowsNetworkFailureCacheFallback,
               let memoryFallback = await api.cachedPlayablePlayURLFallback(bvid: detail.bvid, cid: cid),
               isPlayablePlayURLData(memoryFallback) {
                PlayerMetricsLog.record(
                    .playURLLoaded,
                    metricsID: detail.bvid,
                    title: detail.title,
                    message: playURLLoadedMessage(
                        source: "memoryPlayableCacheAfterNetworkFailure",
                        data: memoryFallback,
                        note: "networkFailureMemoryCache",
                        error: error
                    )
                )
                await applyPlayURLData(
                    memoryFallback,
                    cid: cid,
                    page: pageNumber,
                    source: "memoryPlayableCacheAfterNetworkFailure"
                )
                playbackFallbackMessage = "播放地址接口临时失败，已使用内存可播放线路"
                signpostMessage = "bvid=\(detail.bvid) memory playable cache after failure"
                return
            }
            if await recoverPlayURLAfterFailure(error, cid: cid, page: pageNumber) {
                signpostMessage = "bvid=\(detail.bvid) recovered after failure"
                return
            }
            playVariants = []
            selectedPlayVariant = nil
            isSupplementingPlayQualities = false
            playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
            playURLState = .failed(error.localizedDescription)
            signpostMessage = "bvid=\(detail.bvid) failed \(error.localizedDescription)"
        }
    }

    private func prepareAutomaticCDNRecommendationForPlayback() async {
        let previousCDNPreference = libraryStore.effectivePlaybackCDNPreference
        await PlayerMetricsLog.withSignpostedInterval(
            "VideoDetailCDNRecommendation",
            message: "bvid=\(detail.bvid) preference=\(previousCDNPreference.rawValue)"
        ) {
            await PlaybackCDNProbeCoordinator.shared.prepareRecommendationForImmediatePlaybackIfNeeded(
                libraryStore: libraryStore,
                timeout: cdnRecommendationStartupBudget
            )
        }
        let updatedCDNPreference = libraryStore.effectivePlaybackCDNPreference
        guard updatedCDNPreference != previousCDNPreference,
              updatedCDNPreference != .automatic
        else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "cdnStartupRecommendation=\(updatedCDNPreference.title)"
        )
    }

    private func scheduleAutomaticCDNRecommendationForPlayback() {
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
    }

    private func clearPlayVariantSwitchIfCurrent(_ token: UUID) {
        guard playVariantSwitchToken == token else { return }
        playVariantSwitchTask = nil
        playVariantSwitchToken = nil
        pendingPlayVariantID = nil
        isSwitchingPlayQuality = false
    }

    private func fetchStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        try await api.fetchStartupPlayURL(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: adaptiveStartupPreferredQuality,
            startupQualityCeiling: adaptiveStartupQualityCeiling
        )
    }

    private func startupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        let adaptiveQuality = adaptiveStartupPreferredQuality
        let adaptiveCeiling = adaptiveStartupQualityCeiling
        let key = [
            bvid,
            String(cid),
            page.map(String.init) ?? "-",
            "q\(adaptiveQuality ?? 0)",
            "ceiling\(adaptiveCeiling ?? 0)"
        ].joined(separator: "|")
        if startupPlayURLTaskKey == key, let startupPlayURLTask {
            return try await startupPlayURLTask.value
        }

        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchStartupPlayURL(bvid: bvid, cid: cid, page: page)
        }
        startupPlayURLTask = task
        startupPlayURLTaskKey = key
        defer {
            if startupPlayURLTaskKey == key {
                startupPlayURLTask = nil
                startupPlayURLTaskKey = nil
            }
        }

        return try await task.value
    }

    private func startupPlayURLForDefaultQuality(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        try await fetchPlayURLWithTimeout(
            timeout: playURLLoadTimeoutNanoseconds
        ) { [self] in
            try await startupPlayURL(bvid: bvid, cid: cid, page: page)
        }
    }

    private var playURLRecoveryTimeoutNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 6_500_000_000
            : 6_000_000_000
    }

    private var playURLFullRecoveryTimeoutNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 10_000_000_000
            : 8_500_000_000
    }

    private func recoverPlayURLAfterFailure(
        _ error: Error,
        cid: Int,
        page: Int?
    ) async -> Bool {
        guard !isPlaybackInvalidatedForNavigation else { return false }
        let message = error.localizedDescription
        guard !isPlayURLRateLimited(error) else {
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "skip immediate retry after rate limit \(message)"
            )
            playbackFallbackMessage = "播放接口被临时限制，请稍后重试"
            return false
        }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "retry after failure \(message)"
        )
        await PlayURLCache.shared.invalidate(bvid: detail.bvid)
        await VideoPreloadCenter.shared.invalidatePlayURLCache(for: detail.bvid)
        await api.clearCachedPlayURLFailures(bvid: detail.bvid)
        cancelStartupPlayURLTask()

        do {
            let startupData = try await fetchPlayURLWithTimeout(
                timeout: playURLRecoveryTimeoutNanoseconds
            ) { [self] in
                try await startupPlayURL(bvid: detail.bvid, cid: cid, page: page)
            }
            if await applyRecoveredPlayURLData(
                startupData,
                cid: cid,
                page: page,
                source: "startupRecovery"
            ) {
                return true
            }
        } catch {
            guard !Task.isCancelled else { return false }
            PlayerMetricsLog.record(
                .failed,
                metricsID: detail.bvid,
                title: detail.title,
                message: "startupPlayURLRecovery failed \(error.localizedDescription)"
            )
        }

        guard !isPlaybackInvalidatedForNavigation else { return false }
        await api.clearCachedPlayURLFailures(bvid: detail.bvid)
        cancelStartupPlayURLTask()

        do {
            let fullData = try await fetchPlayURLWithTimeout(
                timeout: playURLFullRecoveryTimeoutNanoseconds
            ) { [self] in
                try await api.fetchPlayURL(
                    bvid: detail.bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: adaptiveStartupPreferredQuality,
                    supplementsQualities: false,
                    preferProgressiveFastStart: false
                )
            }
            if await applyRecoveredPlayURLData(
                fullData,
                cid: cid,
                page: page,
                source: "networkRecovery"
            ) {
                return true
            }
            throw BiliAPIError.emptyPlayURL
        } catch {
            guard !Task.isCancelled else { return false }
            PlayerMetricsLog.record(
                .failed,
                metricsID: detail.bvid,
                title: detail.title,
                message: "playURLRecovery failed \(error.localizedDescription)"
            )
            return false
        }
    }

    private func applyRecoveredPlayURLData(
        _ data: PlayURLData,
        cid: Int,
        page: Int?,
        source: String
    ) async -> Bool {
        guard isPlayablePlayURLData(data) else { return false }
        guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return false }
        await VideoPreloadCenter.shared.store(
            data,
            bvid: detail.bvid,
            cid: cid,
            page: page,
            preferredQuality: adaptiveStartupPreferredQuality,
            targetPreferredQuality: targetPlaybackPreferredQuality,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            warmsMedia: false,
            mediaWarmupDelay: 0
        )
        guard !isPlaybackInvalidatedForNavigation else { return false }
        PlayerMetricsLog.record(
            .playURLLoaded,
            metricsID: detail.bvid,
            title: detail.title,
            message: playURLLoadedMessage(source: source, data: data, note: "recovered")
        )
        await applyPlayURLData(data, cid: cid, page: page, source: source)
        return selectedPlayVariant?.isPlayable == true || playURLState == .loaded
    }

    private func cancelStartupPlayURLTask() {
        startupPlayURLTask?.cancel()
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
    }

    private func isPlayURLRateLimited(_ error: Error) -> Bool {
        if case BiliAPIError.api(let code, _) = error, code == -351 {
            return true
        }
        return false
    }

    private func isPlayablePlayURLData(_ data: PlayURLData) -> Bool {
        data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            .contains(where: \.isPlayable)
    }

    private func playURLLoadedMessage(
        source: String,
        data: PlayURLData,
        note: String? = nil,
        error: Error? = nil
    ) -> String {
        let playableVariants = data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            .filter(\.isPlayable)
        var parts = [
            "source=\(diagnosticToken(source))",
            "variants=\(playableVariants.count)",
            "qualities=\(Self.qualitySummary(playableVariants))",
            "cdn=\(diagnosticToken(libraryStore.effectivePlaybackCDNPreference.rawValue))"
        ]
        if let note, !note.isEmpty {
            parts.append("note=\(diagnosticToken(note))")
        }
        if let error {
            parts.append("error=\(diagnosticToken(error.localizedDescription))")
        }
        return parts.joined(separator: " ")
    }

    private func diagnosticToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        return String(trimmed.map { character in
            character.isWhitespace || character == "|" ? "_" : character
        })
    }

    private func fetchPlayURLWithTimeout(
        timeout: UInt64,
        operation: @escaping () async throws -> PlayURLData
    ) async throws -> PlayURLData {
        try await withThrowingTaskGroup(of: PlayURLData.self) { group -> PlayURLData in
            group.addTask(priority: .userInitiated) {
                try await operation()
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: timeout)
                throw VideoDetailLoadTimeoutError.playURL
            }
            guard let result = try await group.next() else {
                throw VideoDetailLoadTimeoutError.playURL
            }
            group.cancelAll()
            return result
        }
    }

    private func warmCachedPlayInfoIfAvailable() {
        guard let cid = selectedCID, selectedPlayVariant == nil else { return }
        let page = selectedPageNumber
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let data = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                for: self.detail.bvid,
                cid: cid,
                page: page,
                waitsForPending: false,
                preferredQuality: self.adaptiveStartupPreferredQuality
            ) {
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                await self.applyPlayURLData(
                    data,
                    cid: cid,
                    page: page,
                    source: "detailWarmCache",
                    schedulesSupplementalLoad: false
                )
            }
        }
    }

    private func applyPlayURLData(
        _ data: PlayURLData,
        cid: Int?,
        page: Int?,
        source: String = "unknown",
        schedulesSupplementalLoad: Bool = true
    ) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        if let cid {
            guard selectedCID == cid else { return }
        }
        let variants = sortedPlayVariants(data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference))
        lastPlayURLSource = source
        playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
        failedPlayVariantIDs.removeAll()

        guard !variants.isEmpty else {
            playVariants = []
            selectedPlayVariant = nil
            return
        }

        let selectedVariant = preferredDefaultVariant(in: variants)
        let targetVariant = selectedVariant
        guard !isPlaybackInvalidatedForNavigation else { return }
        playVariants = variants
        selectedPlayVariant = selectedVariant
        logSelectedPlayVariant(selectedVariant, availableVariants: variants, source: source)
        if stablePlayerViewModel == nil {
            guard !isPlaybackInvalidatedForNavigation, selectedCID == cid else {
                return
            }
        }
        fastStartUpgradeTask?.cancel()
        fastStartUpgradeTask = nil
        scheduleSelectedStartupPackageWarmupAfterFirstFrame(selectedVariant, cid: cid, page: page)
        updateStablePlayerViewModelIfNeeded()
        playURLState = .loaded
        warmSelectedVariantAfterFirstFrameIfNeeded(selectedVariant, cid: cid, page: page)
        rankPlaybackCDNCandidatesAfterFirstFrameIfNeeded(selectedVariant, cid: cid)
        scheduleHLSRenditionPrebuildAfterFirstFrameIfNeeded(
            startupVariant: selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
        playURLSupplementTask?.cancel()
        playURLSupplementTask = nil
        isSupplementingPlayQualities = false
        if schedulesSupplementalLoad {
            scheduleSupplementalTargetQualityLoadIfNeeded(
                variants: variants,
                cid: cid,
                page: page
            )
        }
    }

    private func scheduleSelectedStartupPackageWarmupAfterFirstFrame(_ variant: PlayVariant?, cid: Int?, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              let cid,
              let variant,
              variant.isPlayable,
              !variant.isProgressiveFastStart
        else { return }
        let variantID = variant.id
        Task(priority: .utility) { [weak self, variant] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.selectedPlayVariant?.id == variantID
            else { return }
            await VideoPreloadCenter.shared.warmVariant(
                variant,
                bvid: self.detail.bvid,
                cid: cid,
                page: page,
                delay: 0.2
            )
        }
    }

    private func optimizedStartupVariant(_ variant: PlayVariant?, source: String) async -> PlayVariant? {
        guard let variant, variant.isPlayable else { return variant }
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let headers = BiliHLSManifestBuilder.httpHeaders(referer: "https://www.bilibili.com/video/\(detail.bvid)")
        let selection = await PlayerMetricsLog.withSignpostedInterval(
            "VideoDetailStartupCDNProbe",
            message: "bvid=\(detail.bvid) source=\(source) q=\(variant.quality)"
        ) {
            await PlaybackStartupURLProbeService.optimizedVariant(
                for: variant,
                cdnPreference: cdnPreference,
                headers: headers,
                timeout: startupURLProbeBudget
            )
        }
        let optimizedVariant = selection.variant
        let didChangeURL = optimizedVariant.videoURL != variant.videoURL
            || optimizedVariant.audioURL != variant.audioURL
        if didChangeURL || selection.videoElapsedMilliseconds != nil || selection.audioElapsedMilliseconds != nil {
            let videoHost = optimizedVariant.videoURL?.host ?? "-"
            let audioHost = optimizedVariant.audioURL?.host ?? "-"
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "startupCDNProbe source=\(source) validated=\(selection.startupValidated) video=\(selection.videoElapsedMilliseconds.map { "\($0)ms" } ?? "-") audio=\(selection.audioElapsedMilliseconds.map { "\($0)ms" } ?? "-") host=\(videoHost) audioHost=\(audioHost)"
            )
        }
        return optimizedVariant
    }

    private var startupURLProbeBudget: TimeInterval {
        let baseBudget: TimeInterval
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            baseBudget = 0.32
        case .unknown:
            baseBudget = 0.24
        case .cellular, .constrained:
            baseBudget = 0.18
        }
        guard playbackAdaptationProfile.shouldRefreshPlaybackCDNProbe else {
            return baseBudget
        }
        return min(cdnRecommendationStartupBudget, baseBudget + 0.08)
    }

    private var cdnRecommendationStartupBudget: TimeInterval {
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 0.28
        case .unknown:
            return 0.22
        case .cellular, .constrained:
            return 0.16
        }
    }

    private func replacingVariant(
        in variants: [PlayVariant],
        matching id: String,
        with replacement: PlayVariant
    ) -> [PlayVariant] {
        variants.map { $0.id == id ? replacement : $0 }
    }

    private func shouldSupplementPlayQualities(for variants: [PlayVariant]) -> Bool {
        false
    }

    private func scheduleSupplementalTargetQualityLoadIfNeeded(
        variants: [PlayVariant],
        cid: Int?,
        page: Int?
    ) {
        guard let cid,
              needsSupplementalTargetQuality(variants)
        else { return }
        scheduleSupplementalPlayURLLoad(
            cid: cid,
            page: page,
            waitsForFirstFrame: true,
            startDelay: 0.12
        )
    }

    private func needsSupplementalTargetQuality(_ variants: [PlayVariant]) -> Bool {
        guard let preferredQuality = targetPlaybackPreferredQuality else { return false }
        let playableVariants = variants.filter(\.isPlayable)
        guard !playableVariants.isEmpty else { return false }
        if [116, 74].contains(preferredQuality) {
            return !playableVariants.contains {
                $0.quality == preferredQuality && variantFrameRate($0) >= 50
            }
        }
        return !playableVariants.contains { $0.quality == preferredQuality }
    }

    private func playVariantsNeedSupplementalFrameRateUpgrade(_ variants: [PlayVariant]) -> Bool {
        let playableVariants = variants.filter(\.isPlayable)
        guard !playableVariants.isEmpty else { return false }
        guard let preferredQuality = libraryStore.preferredVideoQuality else { return false }
        guard [116, 74].contains(preferredQuality) else { return false }
        return !playableVariants.contains {
            $0.quality == preferredQuality && variantFrameRate($0) >= 50
        }
    }

    private func scheduleSupplementalPlayURLLoad(
        cid: Int,
        page: Int?,
        waitsForFirstFrame: Bool = false,
        startDelay: TimeInterval = 0
    ) {
        playURLSupplementTask?.cancel()
        isSupplementingPlayQualities = false
        playURLSupplementTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard !self.isPlaybackInvalidatedForNavigation else { return }
            defer {
                if !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid {
                    self.isSupplementingPlayQualities = false
                }
            }
            do {
                if waitsForFirstFrame {
                    let didPresentPlayback = await self.waitForFirstFrameOrFailure()
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid else { return }
                    guard didPresentPlayback else { return }
                }
                if startDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid else { return }
                }
                guard !self.isPlaybackInvalidatedForNavigation else { return }
                self.isSupplementingPlayQualities = true
                let supplementStart = CACurrentMediaTime()
                let supplementalPreferredQuality = self.targetPlaybackPreferredQuality
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "start preferred=\(supplementalPreferredQuality ?? 0)"
                )

                let data = try await self.api.fetchPlayURL(
                    bvid: self.detail.bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: supplementalPreferredQuality,
                    supplementsQualities: true
                )
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid else { return }
                await VideoPreloadCenter.shared.store(
                    data,
                    bvid: self.detail.bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: self.targetPlaybackPreferredQuality,
                    targetPreferredQuality: self.targetPlaybackPreferredQuality,
                    cdnPreference: self.libraryStore.effectivePlaybackCDNPreference,
                    warmsMedia: false,
                    mediaWarmupDelay: 0
                )
                guard !self.isPlaybackInvalidatedForNavigation else { return }

                let variants = data.playVariants(cdnPreference: self.libraryStore.effectivePlaybackCDNPreference)
                let supplementMilliseconds = self.formatMilliseconds(self.elapsedMilliseconds(since: supplementStart))
                guard !variants.isEmpty else {
                    PlayerMetricsLog.record(
                        .qualitySupplement,
                        metricsID: self.detail.bvid,
                        title: self.detail.title,
                        message: "empty \(supplementMilliseconds)"
                    )
                    return
                }

                let currentVariant = self.selectedPlayVariant
                self.playVariants = self.mergedSupplementalVariants(
                    variants,
                    preserving: currentVariant
                )
                if self.shouldAutoUpgradeSupplementalVariant(from: currentVariant),
                   let preferredVariant = self.preferredDefaultVariant(in: self.playVariants),
                   preferredVariant.id != currentVariant?.id,
                   let currentVariant {
                    if let matchingVariant = self.playVariants.first(where: { $0.id == currentVariant.id }) {
                        self.selectedPlayVariant = matchingVariant
                    }
                    PlayerMetricsLog.record(
                        .qualitySupplement,
                        metricsID: self.detail.bvid,
                        title: self.detail.title,
                        message: "success \(supplementMilliseconds) targetAvailable keep q\(currentVariant.quality) target q\(preferredVariant.quality) variants=\(variants.filter(\.isPlayable).count)"
                    )
                } else if let currentVariant,
                          let matchingVariant = self.playVariants.first(where: { $0.id == currentVariant.id }) {
                    self.selectedPlayVariant = matchingVariant
                    PlayerMetricsLog.record(
                        .qualitySupplement,
                        metricsID: self.detail.bvid,
                        title: self.detail.title,
                        message: "success \(supplementMilliseconds) keep q\(matchingVariant.quality) variants=\(variants.filter(\.isPlayable).count)"
                    )
                } else {
                    self.selectedPlayVariant = self.preferredDefaultVariant(in: self.playVariants)
                    PlayerMetricsLog.record(
                        .qualitySupplement,
                        metricsID: self.detail.bvid,
                        title: self.detail.title,
                        message: "success \(supplementMilliseconds) selected q\(self.selectedPlayVariant?.quality ?? 0) variants=\(variants.filter(\.isPlayable).count)"
                    )
                    self.updateStablePlayerViewModelIfNeeded()
                }
                if self.playbackAdaptationProfile.shouldWarmSupplementalVariants,
                   !PlaybackEnvironment.current.shouldPreferConservativePlayback {
                    self.warmLikelySupplementalVariantAfterFirstFrame(cid: cid, page: page)
                }
            } catch {
                guard !Task.isCancelled else { return }
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "failed \(error.localizedDescription)"
                )
            }
            self.playURLSupplementTask = nil
        }
    }

    private func mergedSupplementalVariants(
        _ variants: [PlayVariant],
        preserving currentVariant: PlayVariant?
    ) -> [PlayVariant] {
        let sortedVariants = sortedPlayVariants(variants)
        guard let currentVariant,
              currentVariant.isPlayable,
              !sortedVariants.contains(where: { $0.id == currentVariant.id })
        else {
            return sortedVariants
        }
        return [currentVariant] + sortedVariants
    }

    private func shouldAutoUpgradeSupplementalVariant(from currentVariant: PlayVariant?) -> Bool {
        guard !didSelectPlayVariantManually else { return false }
        guard let currentVariant, currentVariant.isPlayable else { return selectedPlayVariant == nil }
        guard let preferredVariant = preferredDefaultVariant(in: playVariants),
              preferredVariant.isPlayable,
              preferredVariant.id != currentVariant.id
        else { return false }
        return variant(preferredVariant, isBetterThan: currentVariant)
    }

    private func variant(_ candidate: PlayVariant, isBetterThan current: PlayVariant) -> Bool {
        if candidate.isProgressiveFastStart != current.isProgressiveFastStart {
            return !candidate.isProgressiveFastStart && current.isProgressiveFastStart
        }
        if candidate.quality != current.quality {
            return candidate.quality > current.quality
        }
        let candidateFPS = variantFrameRate(candidate)
        let currentFPS = variantFrameRate(current)
        if candidateFPS != currentFPS {
            return candidateFPS > currentFPS
        }
        return (candidate.bandwidth ?? 0) > (current.bandwidth ?? 0)
    }

    private func variantFrameRate(_ variant: PlayVariant) -> Double {
        if let frameRate = DASHStream.numericFrameRate(from: variant.frameRate) {
            return frameRate
        }
        if [116, 74].contains(variant.quality) {
            return 60
        }
        if variant.title.contains("高帧")
            || variant.title.contains("60")
            || variant.badge?.contains("高帧") == true
            || variant.badge?.contains("60") == true {
            return 60
        }
        return 0
    }

    func updateStablePlayerViewModelIfNeeded(
        resumeTimeOverride: TimeInterval? = nil,
        shouldResumePlayback: Bool? = nil,
        playbackRateOverride: BiliPlaybackRate? = nil,
        preservesPreviousPlayerUntilFirstFrame: Bool = false
    ) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard let variant = selectedPlayVariant, variant.isPlayable else {
            finishPlaybackStartupWaiters(with: nil)
            stablePlayerViewModel?.stop()
            stablePlayerViewModel = nil
            clearPlaybackTransitionPlayer()
            stablePlayerIdentity = nil
            stablePlayerErrorCancellable = nil
            stablePlayerFirstFrameCancellable = nil
            return
        }

        let identity = playerIdentity(for: variant)
        guard stablePlayerIdentity != identity else {
            if let resumeTimeOverride {
                updateResumeDiagnostics(
                    source: resumeSourceTitle(for: "stableIdentityResume"),
                    targetTime: resumeTimeOverride,
                    cid: selectedCID,
                    status: "同一播放器，准备应用",
                    reason: "播放器身份未变化"
                )
                applyResumeTimeToCurrentPlayerIfPossible(
                    resumeTimeOverride,
                    reason: "stableIdentityResume",
                    shouldResumePlayback: shouldResumePlayback,
                    playbackRateOverride: playbackRateOverride
                )
            }
            return
        }

        let previousPlayer = stablePlayerViewModel
        let localResumeTime = currentPlaybackResumeTime()
        let resumeCandidate = playbackResumeCandidate(
            resumeTimeOverride: resumeTimeOverride,
            localResumeTime: localResumeTime
        )
        let resumeTime = resumeCandidate.time
        let shouldAutoplay = shouldResumePlayback ?? currentPlaybackIntent()
        let playbackRate = playbackRateOverride ?? previousPlayer?.playbackRate ?? .x10
        if preservesPreviousPlayerUntilFirstFrame {
            beginPlaybackTransition(from: previousPlayer)
        } else {
            previousPlayer?.stop(reason: .replacedByAnotherPlayer)
            clearPlaybackTransitionPlayer()
        }
        stablePlayerIdentity = identity
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerCreate",
            message: "bvid=\(detail.bvid) cid=\(selectedCID ?? 0) q=\(variant.quality)"
        )
        var signpostMessage = "bvid=\(detail.bvid) creating"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerCreate",
                signpostState,
                message: signpostMessage
            )
        }
        let alternateVideoRenditions = hlsAlternateVideoRenditions(for: variant)
        recordHLSVideoVariantPlan(
            startupVariant: variant,
            alternateVideoRenditions: alternateVideoRenditions
        )
        let playerViewModel = PlayerStateViewModel(
            videoURL: variant.videoURL,
            audioURL: variant.audioURL,
            videoStream: variant.videoStream,
            audioStream: variant.audioStream,
            alternateVideoRenditions: alternateVideoRenditions,
            title: detail.title,
            referer: "https://www.bilibili.com/video/\(detail.bvid)",
            durationHint: detail.duration.map(TimeInterval.init),
            resumeTime: resumeTime,
            startupResumePolicy: resumeTime > 0.25 ? .immediate : .deferred,
            dynamicRange: variant.dynamicRange,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            metricsID: detail.bvid
        )
        playerViewModel.onBufferingPressure = { [weak self] count in
            self?.handleBufferingPressure(count)
        }
        playerViewModel.onFirstFramePresented = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.finishPlaybackStartupWaiters(with: .firstFrame)
            self.releasePlaybackTransitionPlayer(after: Self.playbackTransitionReleaseDelayNanoseconds)
        }
        playerViewModel.setPlaybackRate(playbackRate)
        playerViewModel.setPlaybackIntent(shouldAutoplay)
        stablePlayerViewModel = playerViewModel
        updateResumeDiagnostics(
            source: resumeCandidate.sourceTitle,
            targetTime: resumeTime > 0.25 ? resumeTime : nil,
            cid: resumeCandidate.cid,
            status: resumeTime > 0.25 ? "创建播放器，等待首轮 seek" : "从头播放",
            reason: resumeCandidate.reason
        )
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        PlayerMetricsLog.record(
            .playerCreated,
            metricsID: detail.bvid,
            title: detail.title,
            message: "\(variant.title) · CDN \(cdnPreference.title)"
        )
        if let host = variant.videoURL?.host ?? variant.audioURL?.host {
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "host=\(host) cdn=\(cdnPreference.rawValue) quality=\(variant.quality)"
            )
        }
        observePlaybackErrors(playerViewModel, variant: variant)
        observeFirstFrameMetrics(playerViewModel, variant: variant, resumeCandidate: resumeCandidate)
        applySponsorBlockSegmentsToPlayer()
        scheduleSponsorBlockSegmentsAfterFirstFrame()
        if shouldAutoplay {
            playerViewModel.play()
        }
        signpostMessage = "bvid=\(detail.bvid) ready autoplay=\(shouldAutoplay)"
    }

    private func beginPlaybackTransition(from player: PlayerStateViewModel?) {
        guard let player,
              player.hasPresentedPlayback,
              !player.isTerminated
        else {
            clearPlaybackTransitionPlayer()
            return
        }
        if let transitionPlayer = playbackTransitionPlayerViewModel,
           transitionPlayer !== player {
            clearPlaybackTransitionPlayer()
        } else {
            playbackTransitionReleaseTask?.cancel()
            playbackTransitionReleaseTask = nil
        }
        let snapshot = player.makePlaybackTransitionSnapshot()
        player.prepareForVisualPlaybackTransition()
        playbackTransitionPlayerViewModel = player
        playbackTransitionSnapshot = snapshot
        playbackTransitionFallbackCoverURL = playbackTransitionCoverURL()
        playbackTransitionOpacity = 1
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup transitionHold snapshot=\(snapshot != nil ? "frame" : "cover")"
        )
        releasePlaybackTransitionPlayer(after: Self.playbackTransitionMaximumRetainNanoseconds)
    }

    private func releasePlaybackTransitionPlayer(after delay: UInt64) {
        guard playbackTransitionPlayerViewModel != nil else { return }
        playbackTransitionReleaseTask?.cancel()
        let transitionPlayer = playbackTransitionPlayerViewModel
        playbackTransitionReleaseTask = Task { @MainActor [weak self, weak transitionPlayer] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self,
                  !Task.isCancelled,
                  let transitionPlayer,
                  self.playbackTransitionPlayerViewModel === transitionPlayer
            else { return }
            self.playbackTransitionOpacity = 0
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: self.detail.bvid,
                title: self.detail.title,
                message: "stagedStartup transitionFade"
            )
            try? await Task.sleep(nanoseconds: Self.playbackTransitionFadeDurationNanoseconds)
            guard !Task.isCancelled,
                  self.playbackTransitionPlayerViewModel === transitionPlayer
            else { return }
            self.finishPlaybackTransitionRelease(transitionPlayer)
        }
    }

    private func clearPlaybackTransitionPlayer() {
        playbackTransitionReleaseTask?.cancel()
        playbackTransitionReleaseTask = nil
        let transitionPlayer = playbackTransitionPlayerViewModel
        playbackTransitionPlayerViewModel = nil
        playbackTransitionSnapshot = nil
        playbackTransitionFallbackCoverURL = nil
        playbackTransitionOpacity = 0
        guard let transitionPlayer else { return }
        if stablePlayerViewModel !== transitionPlayer {
            transitionPlayer.stop(reason: .replacedByAnotherPlayer)
        }
    }

    private func finishPlaybackTransitionRelease(_ transitionPlayer: PlayerStateViewModel) {
        playbackTransitionReleaseTask = nil
        guard playbackTransitionPlayerViewModel === transitionPlayer else { return }
        playbackTransitionPlayerViewModel = nil
        playbackTransitionSnapshot = nil
        playbackTransitionFallbackCoverURL = nil
        playbackTransitionOpacity = 0
        if stablePlayerViewModel !== transitionPlayer {
            transitionPlayer.stop(reason: .replacedByAnotherPlayer)
        }
    }

    private func playbackTransitionCoverURL() -> URL? {
        guard let cover = detail.pic?.normalizedBiliURL() else { return nil }
        let width = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 480 : 720
        let height = Int((Double(width) * 9.0 / 16.0).rounded())
        return URL(string: cover.biliCoverThumbnailURL(width: width, height: height))
            ?? URL(string: cover)
    }

    private func currentPlaybackResumeTime() -> TimeInterval {
        guard let player = stablePlayerViewModel else { return 0 }
        let snapshotTime = player.playbackSnapshot().currentTime
        let bestTime = max(snapshotTime ?? 0, player.currentTime)
        guard bestTime.isFinite else { return 0 }
        return max(bestTime, 0)
    }

    @discardableResult
    private func applyResumeTimeToCurrentPlayerIfPossible(
        _ resumeTime: TimeInterval,
        reason: String,
        shouldResumePlayback: Bool?,
        playbackRateOverride: BiliPlaybackRate?
    ) -> Bool {
        let sourceTitle = resumeSourceTitle(for: reason)
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailResume",
            message: "source=\(sourceTitle) reason=\(reason) target=\(String(format: "%.2f", resumeTime))"
        )
        var signpostMessage = "source=\(sourceTitle) pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailResume",
                signpostState,
                message: signpostMessage
            )
        }
        guard let player = stablePlayerViewModel else {
            updateResumeDiagnostics(
                source: sourceTitle,
                targetTime: resumeTime,
                cid: selectedCID,
                status: "等待播放器",
                reason: reason
            )
            signpostMessage = "source=\(sourceTitle) waiting player"
            return false
        }
        let snapshot = player.playbackSnapshot()
        let currentTime = max(snapshot.currentTime ?? 0, player.currentTime)
        guard currentTime.isFinite else {
            updateResumeDiagnostics(
                source: sourceTitle,
                targetTime: resumeTime,
                cid: selectedCID,
                status: "等待时间轴",
                reason: reason
            )
            signpostMessage = "source=\(sourceTitle) waiting timeline"
            return false
        }
        guard resumeTime > currentTime + 2 else {
            updateResumeDiagnostics(
                source: sourceTitle,
                targetTime: resumeTime,
                cid: selectedCID,
                status: "跳过，当前位置更新",
                reason: reason,
                currentTime: currentTime
            )
            signpostMessage = "source=\(sourceTitle) stale"
            return false
        }
        if let playbackRateOverride {
            player.setPlaybackRate(playbackRateOverride)
        }
        let wasPlaying = shouldResumePlayback ?? (player.wantsAutoplay || player.isPlaying || snapshot.isPlaying)
        let didApply = player.applyStartupResumeTime(resumeTime, reason: reason)
        updateResumeDiagnostics(
            source: sourceTitle,
            targetTime: resumeTime,
            cid: selectedCID,
            status: didApply ? "已提交并完成 seek" : "已排队等待播放器就绪",
            reason: reason,
            currentTime: currentTime
        )
        signpostMessage = "source=\(sourceTitle) \(didApply ? "applied" : "queued")"
        if wasPlaying {
            player.setPlaybackIntent(true)
            player.resumePlaybackAfterUserSeek()
        }
        return didApply
    }

    private func playbackResumeCandidate(
        resumeTimeOverride: TimeInterval?,
        localResumeTime: TimeInterval
    ) -> PlaybackResumeCandidate {
        if let resumeTimeOverride, resumeTimeOverride > 0.25 {
            return PlaybackResumeCandidate(
                time: resumeTimeOverride,
                sourceTitle: resumeSourceTitle(for: "override"),
                reason: "显式续播目标",
                cid: selectedCID
            )
        }

        if localResumeTime > 0.25 {
            return PlaybackResumeCandidate(
                time: localResumeTime,
                sourceTitle: "当前播放",
                reason: "复用当前播放器快照",
                cid: selectedCID
            )
        }

        return PlaybackResumeCandidate(
            time: 0,
            sourceTitle: "无",
            reason: "没有可用历史进度",
            cid: selectedCID
        )
    }

    private func resumeSourceTitle(for reason: String) -> String {
        switch reason {
        case "stableIdentityResume", "override":
            return "指定进度"
        default:
            return "当前播放"
        }
    }

    private func updateResumeDiagnostics(
        source: String,
        targetTime: TimeInterval?,
        cid: Int?,
        status: String,
        reason: String,
        currentTime: TimeInterval? = nil
    ) {
        let diagnostics = PlaybackResumeDiagnostics(
            sourceTitle: source,
            targetTime: targetTime,
            cid: cid,
            statusTitle: status,
            reason: reason,
            currentTime: currentTime
        )
        guard diagnostics != resumeDiagnostics else { return }
        resumeDiagnostics = diagnostics

        let targetText = targetTime.map { String(format: "%.2fs", $0) } ?? "none"
        let currentText = currentTime.map { String(format: "%.2fs", $0) } ?? "unknown"
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: detail.bvid,
            title: detail.title,
            message: "source=\(source) status=\(status) target=\(targetText) cid=\(cid ?? 0) current=\(currentText) reason=\(reason)"
        )
    }

    private func currentPlaybackIntent() -> Bool {
        guard let player = stablePlayerViewModel else { return true }
        let snapshot = player.playbackSnapshot()
        return player.wantsAutoplay || player.isPlaying || snapshot.isPlaying
    }

    private func observePlaybackErrors(_ playerViewModel: PlayerStateViewModel, variant: PlayVariant) {
        stablePlayerErrorCancellable = playerViewModel.$errorMessage
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] message in
                guard let self,
                      self.stablePlayerViewModel === playerViewModel
                else { return }
                self.finishPlaybackStartupWaiters(with: .failed)
                self.handlePlaybackError(message, for: variant)
            }
    }

    private func observeFirstFrameMetrics(
        _ playerViewModel: PlayerStateViewModel,
        variant: PlayVariant,
        resumeCandidate: PlaybackResumeCandidate
    ) {
        stablePlayerFirstFrameCancellable = playerViewModel.$firstFrameElapsedMilliseconds
            .compactMap { $0 }
            .first()
            .sink { [weak self, weak playerViewModel] firstFrameElapsedMilliseconds in
                guard let self,
                      let playerViewModel,
                      self.stablePlayerViewModel === playerViewModel
                else { return }
                self.finishPlaybackStartupWaiters(with: .firstFrame)
                self.recordStartupPlaybackMetrics(
                    variant: variant,
                    resumeCandidate: resumeCandidate,
                    playerViewModel: playerViewModel,
                    firstFrameElapsedMilliseconds: firstFrameElapsedMilliseconds
                )
                self.releasePlaybackTransitionPlayer(after: Self.playbackTransitionReleaseDelayNanoseconds)
            }
    }

    private func recordStartupPlaybackMetrics(
        variant: PlayVariant,
        resumeCandidate: PlaybackResumeCandidate,
        playerViewModel: PlayerStateViewModel,
        firstFrameElapsedMilliseconds: Int
    ) {
        let detailElapsed = elapsedMilliseconds(since: detailLoadStartTime)
        let playURLElapsed = playURLElapsedMilliseconds ?? elapsedMilliseconds(since: playURLLoadStartTime)
        let prepareElapsed = playerViewModel.prepareElapsedMilliseconds
        let playbackElapsed = playerViewModel.firstFrameElapsedMilliseconds ?? firstFrameElapsedMilliseconds
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let environment = PlaybackEnvironment.current
        let resumeText = resumeCandidate.time > 0.25
            ? String(format: "%.2fs", resumeCandidate.time)
            : "none"
        let summary = [
            "detail=\(formattedMilliseconds(detailElapsed))",
            "playurl=\(formattedMilliseconds(playURLElapsed))",
            "prepare=\(formattedMilliseconds(prepareElapsed))",
            "firstFrame=\(formatMilliseconds(playbackElapsed))",
            "resume=\(resumeText)",
            "cid=\(selectedCID ?? 0)",
            "source=\(lastPlayURLSource ?? "-")",
            "q=\(variant.quality)",
            "targetQ=\(targetPlaybackPreferredQuality ?? 0)",
            "cdn=\(cdnPreference.rawValue)",
            "network=\(environment.networkClass.performanceSampleKey)"
        ].joined(separator: " ")
        PlayerMetricsLog.signpostEvent(
            "VideoDetailStartupBreakdown",
            message: summary
        )
        PlayerMetricsLog.logger.info(
            "startupBreakdown bvid=\(self.detail.bvid, privacy: .public) \(summary, privacy: .public)"
        )
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: detail.bvid,
            title: detail.title,
            message: summary
        )
    }

    private func handlePlaybackError(_ message: String, for failedVariant: PlayVariant) {
        guard !isPlaybackInvalidatedForNavigation,
              !hasPendingNavigationInterruption,
              selectedPlayVariant?.id == failedVariant.id
        else { return }
        failedPlayVariantIDs.insert(failedVariant.id)
        temporarilyAvoidCurrentAutomaticPlaybackCDN(reason: "playbackError")
        PlaybackCDNProbeCoordinator.shared.refreshForPlaybackPressure(libraryStore: libraryStore)
        if playbackFailurePrefersPlayURLReload(message),
           schedulePlaybackRecoveryReload(after: message, failedVariant: failedVariant) {
            return
        }
        guard let fallbackVariant = playbackFallbackVariant(excluding: failedVariant) else {
            schedulePlaybackRecoveryReload(after: message, failedVariant: failedVariant)
            return
        }

        let resumeTime = currentPlaybackResumeTime()
        let shouldResumePlayback = currentPlaybackIntent()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        PlayerMetricsLog.logger.error(
            "playbackFallback from=\(failedVariant.quality, privacy: .public) to=\(fallbackVariant.quality, privacy: .public) error=\(message, privacy: .public)"
        )
        playbackFallbackMessage = failedVariant.dynamicRange == .dolbyVision
            ? "杜比视界当前不可播放，已切换到 \(fallbackVariant.title)"
            : "当前线路播放失败，已切换到 \(fallbackVariant.title)"
        selectedPlayVariant = fallbackVariant
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRate
        )
    }

    private func playbackFailurePrefersPlayURLReload(_ message: String) -> Bool {
        message.contains("播放地址已过期")
            || message.contains("重新获取播放地址")
    }

    private func handleBufferingPressure(_ count: Int) {
        guard !isPlaybackInvalidatedForNavigation,
              count >= 2,
              count != lastBufferingCDNRefreshCount
        else { return }
        lastBufferingCDNRefreshCount = count
        let previousPreference = libraryStore.effectivePlaybackCDNPreference
        temporarilyAvoidCurrentAutomaticPlaybackCDN(reason: "bufferingPressure count=\(count)")
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "bufferingPressure count=\(count) cdnRefresh=queued"
        )
        PlaybackCDNProbeCoordinator.shared.refreshForPlaybackPressure(libraryStore: libraryStore)
        bufferingCDNRefreshTask?.cancel()
        bufferingCDNRefreshTask = Task { @MainActor [weak self, previousPreference] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled else { return }
            let updatedPreference = self.libraryStore.effectivePlaybackCDNPreference
            if updatedPreference != previousPreference {
                PlayerMetricsLog.record(
                    .network,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "bufferingPressure cdnPreference \(previousPreference.rawValue)->\(updatedPreference.rawValue)"
                )
            }
            self.bufferingCDNRefreshTask = nil
        }
    }

    private func temporarilyAvoidCurrentAutomaticPlaybackCDN(reason: String) {
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        let currentPreference = libraryStore.effectivePlaybackCDNPreference
        guard currentPreference != .automatic,
              libraryStore.temporarilyAvoidAutomaticPlaybackCDN(currentPreference)
        else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "automaticCDNAvoided cdn=\(currentPreference.rawValue) reason=\(diagnosticToken(reason))"
        )
    }

    @discardableResult
    private func schedulePlaybackRecoveryReload(after message: String, failedVariant: PlayVariant) -> Bool {
        guard playbackRecoveryAttemptCount < 2,
              !playURLState.isLoading,
              !isPlaybackInvalidatedForNavigation
        else { return false }
        playbackRecoveryAttemptCount += 1
        let attempt = playbackRecoveryAttemptCount
        let resumeTime = currentPlaybackResumeTime()
        let shouldResumePlayback = currentPlaybackIntent()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        playbackFallbackMessage = playbackFailurePrefersPlayURLReload(message)
            ? "播放地址可能已过期，正在重新获取播放地址（第 \(attempt) 次）"
            : "当前线路播放失败，正在重新获取播放地址（第 \(attempt) 次）"
        PlayerMetricsLog.record(
            .failed,
            metricsID: detail.bvid,
            title: detail.title,
            message: "recoveryReload attempt=\(attempt) q=\(failedVariant.quality) error=\(message)"
        )
        selectedPlayVariant = nil
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        finishPlaybackStartupWaiters(with: nil)
        playURLState = .idle
        Task { @MainActor [weak self] in
            guard let self else { return }
            await PlayURLCache.shared.invalidate(bvid: self.detail.bvid)
            await VideoPreloadCenter.shared.invalidatePlayURLCache(for: self.detail.bvid)
            await self.api.clearCachedPlayURLFailures(bvid: self.detail.bvid)
            self.cancelStartupPlayURLTask()
            await self.loadPlayURL(mode: .playbackRecovery)
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedPlayVariant?.isPlayable == true
            else { return }
            self.updateStablePlayerViewModelIfNeeded(
                resumeTimeOverride: resumeTime,
                shouldResumePlayback: shouldResumePlayback,
                playbackRateOverride: playbackRate
            )
        }
        return true
    }

    private func playbackFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        if failedVariant.dynamicRange == .dolbyVision,
           let dolbyFallback = dolbyPlaybackFallbackVariant(excluding: failedVariant) {
            return dolbyFallback
        }

        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && !failedPlayVariantIDs.contains($0.id)
            }
        guard !candidates.isEmpty else { return nil }

        let lowerOrEqualQuality = candidates
            .filter { $0.quality <= failedVariant.quality }
        if let fallback = lowerOrEqualQuality
            .first(where: { !$0.isProgressiveFastStart }) {
            return fallback
        }
        return lowerOrEqualQuality.first
            ?? candidates.first(where: { !$0.isProgressiveFastStart })
            ?? candidates.first
    }

    private func dolbyPlaybackFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && !failedPlayVariantIDs.contains($0.id)
                    && $0.dynamicRange != .dolbyVision
                    && !$0.isProgressiveFastStart
            }
        let preferredFallbackQualities = [112, 116, 120, 80, 74, 64, 32]
        for quality in preferredFallbackQualities {
            if let variant = candidates.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return candidates.first
            ?? sortedPlayVariants(playVariants).first {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && $0.dynamicRange != .dolbyVision
            }
    }

    private func playerIdentity(for variant: PlayVariant) -> String {
        "\(selectedCID ?? 0)-\(variant.id)"
    }

    private func hlsAlternateVideoRenditions(for startupVariant: PlayVariant) -> [PlayerVideoRenditionSource] {
        []
    }

    private func recordHLSVideoVariantPlan(
        startupVariant: PlayVariant,
        alternateVideoRenditions: [PlayerVideoRenditionSource]
    ) {
        guard !alternateVideoRenditions.isEmpty else { return }
        let qualities = [startupVariant.quality] + alternateVideoRenditions.map(\.quality)
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: detail.bvid,
            title: detail.title,
            message: "plannedDetailVideo=\(Self.hlsQualitySummary(qualities))"
        )
    }

    private func hlsAlternatePlayVariantCandidates(
        startupVariant: PlayVariant,
        targetVariant: PlayVariant
    ) -> [PlayVariant] {
        let limit = hlsAlternateVideoRenditionLimit
        guard limit > 0 else { return [] }
        let candidates = sortedPlayVariants(playVariants)
            .filter { isHLSAlternateVideoVariant($0, forStartupVariant: startupVariant) }
        guard !candidates.isEmpty else { return [] }

        var selected = [PlayVariant]()
        var seen = Set<String>()
        func append(_ variant: PlayVariant?) {
            guard selected.count < limit,
                  let variant,
                  seen.insert(variant.id).inserted
            else { return }
            selected.append(variant)
        }

        if isHLSAlternateVideoVariant(targetVariant, forStartupVariant: startupVariant) {
            append(targetVariant)
        }
        for quality in hlsManualSwitchWarmupQualityOrder(targetQuality: targetVariant.quality) {
            append(candidates.first { $0.quality == quality })
        }
        for candidate in candidates {
            append(candidate)
        }
        return selected
    }

    private func isHLSAlternateVideoVariant(_ variant: PlayVariant, forStartupVariant startupVariant: PlayVariant) -> Bool {
        variant.isPlayable
            && variant.id != startupVariant.id
            && variant.audioURL == startupVariant.audioURL
            && variant.dynamicRange == startupVariant.dynamicRange
            && variant.videoStream?.isHardwareDecodingCompatibleVideo == true
            && variant.videoURL != nil
            && variantsShareVideoCodecFamily(variant, startupVariant)
            && variantsShareStartupFrameRateClass(variant, startupVariant)
    }

    private var hlsAlternateVideoRenditionLimit: Int {
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 3
        case .unknown:
            return 2
        case .cellular, .constrained:
            return 1
        }
    }

    private func hlsManualSwitchWarmupQualityOrder(targetQuality: Int) -> [Int] {
        var qualities = [Int]()
        func append(_ quality: Int) {
            guard !qualities.contains(quality) else { return }
            qualities.append(quality)
        }
        append(targetQuality)
        [112, 80, 64, 32].forEach(append)
        return qualities
    }

    private nonisolated static func hlsQualitySummary(_ qualities: [Int]) -> String {
        var seen = Set<Int>()
        let uniqueQualities = qualities.filter { seen.insert($0).inserted }
        guard !uniqueQualities.isEmpty else { return "-" }
        return uniqueQualities
            .map { "q\($0)" }
            .joined(separator: "/")
    }

    private func sponsorBlockIdentity(for bvid: String, cid: Int) -> String {
        "\(bvid)-\(cid)"
    }

    private var selectedPageNumber: Int? {
        guard let selectedCID else { return nil }
        guard let page = detail.pages?.first(where: { $0.cid == selectedCID })?.page,
              page > 1
        else { return nil }
        return page
    }

    private var selectedPage: VideoPage? {
        guard let selectedCID else { return detail.pages?.first }
        return detail.pages?.first(where: { $0.cid == selectedCID }) ?? detail.pages?.first
    }

    var playbackAdaptationProfile: PlayerPlaybackAdaptationProfile {
        PlayerPerformanceStore.shared.playbackAdaptationProfile(
            for: detail.bvid,
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
    }

    var targetPlaybackPreferredQuality: Int? {
        libraryStore.preferredVideoQuality ?? LibraryStore.defaultPreferredVideoQuality
    }

    var adaptiveStartupPreferredQuality: Int? {
        targetPlaybackPreferredQuality
    }

    var adaptiveStartupQualityCeiling: Int? {
        nil
    }

    private func preferredDefaultVariant(in variants: [PlayVariant]) -> PlayVariant? {
        preferredDefaultVariant(in: variants, preferredQuality: nil)
    }

    private func preferredDefaultVariant(in variants: [PlayVariant], preferredQuality: Int?) -> PlayVariant? {
        let playableVariants = sortedPlayVariants(variants).filter(\.isPlayable)
        let playbackEnvironment = PlaybackEnvironment.current

        if let preferredVariant = storedPreferredVariant(in: playableVariants, preferredQuality: preferredQuality) {
            return preferredVariant
        }
        if preferredQuality != nil {
            return nil
        }

        if let defaultVariant = playableVariants.first(where: { $0.quality == LibraryStore.defaultPreferredVideoQuality }) {
            return defaultVariant
        }

        let preferredQualities = playbackEnvironment.preferredQualityLadder

        for quality in preferredQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }

        return playableVariants.first ?? variants.first
    }

    private func shouldRefetchForPreferredQuality(_ data: PlayURLData) -> Bool {
        guard let preferredQuality = targetPlaybackPreferredQuality else { return false }
        if [116, 74].contains(preferredQuality) {
            let variants = data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            if variants.contains(where: {
                $0.isPlayable
                    && $0.quality == preferredQuality
                    && variantFrameRate($0) >= 50
            }) {
                return false
            }
            let advertisesPreferredQuality = data.acceptQuality?.contains(preferredQuality) == true
                || data.supportFormats?.contains(where: { $0.quality == preferredQuality }) == true
                || data.dash?.video?.contains(where: { $0.id == preferredQuality }) == true
                || data.quality == preferredQuality
            if advertisesPreferredQuality {
                return true
            }
        }
        return data.shouldRefetchForPreferredQuality(preferredQuality)
    }

    private func shouldRefetchForStartupQuality(_ data: PlayURLData) -> Bool {
        !data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            .contains(where: \.isPlayable)
    }

    private func logSelectedPlayVariant(
        _ variant: PlayVariant?,
        availableVariants: [PlayVariant],
        source: String
    ) {
        let environment = PlaybackEnvironment.current
        let selectedFPS = variant.flatMap { DASHStream.displayFrameRate(from: $0.frameRate) } ?? "-"
        PlayerMetricsLog.logger.info(
            "selectedVariant source=\(source, privacy: .public) bvid=\(self.detail.bvid, privacy: .public) preferred=\(self.libraryStore.preferredVideoQuality ?? 0, privacy: .public) selectedQ=\(variant?.quality ?? 0, privacy: .public) selectedTitle=\(variant?.title ?? "-", privacy: .public) codec=\(variant?.codec ?? "-", privacy: .public) fps=\(selectedFPS, privacy: .public) bandwidth=\(variant?.bandwidth ?? 0, privacy: .public) progressive=\((variant?.isProgressiveFastStart ?? false), privacy: .public) conservative=\(environment.shouldPreferConservativePlayback, privacy: .public) available=\(Self.qualitySummary(availableVariants), privacy: .public)"
        )
    }

    private nonisolated static func qualitySummary(_ variants: [PlayVariant]) -> String {
        let summary = variants
            .filter(\.isPlayable)
            .map { variant in
                let kind = variant.isProgressiveFastStart ? "p" : "d"
                return "\(variant.quality)\(kind)"
            }
            .joined(separator: ",")
        return summary.isEmpty ? "-" : summary
    }

    private func storedPreferredVariant(in playableVariants: [PlayVariant], preferredQuality: Int?) -> PlayVariant? {
        guard let preferredQuality = preferredQuality
                ?? (didSelectPlayVariantManually
                    ? libraryStore.preferredVideoQuality
                    : targetPlaybackPreferredQuality)
        else { return nil }
        let sortedVariants = sortedPlayVariants(playableVariants)
        if let exactVariant = sortedVariants.first(where: { $0.quality == preferredQuality }) {
            return exactVariant
        }

        guard let preferredIndex = LibraryStore.supportedVideoQualities.firstIndex(of: preferredQuality) else {
            return nil
        }
        let fallbackQualities = LibraryStore.supportedVideoQualities.dropFirst(preferredIndex + 1)
        for quality in fallbackQualities {
            if let variant = sortedVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return nil
    }

    private func automaticStartupVariant(in variants: [PlayVariant], targetVariant: PlayVariant?) -> PlayVariant? {
        guard !didSelectPlayVariantManually,
              let startupQuality = adaptiveStartupPreferredQuality,
              let targetVariant,
              startupQuality < targetVariant.quality
        else { return nil }
        guard let startupVariant = preferredDefaultVariant(
            in: variants,
            preferredQuality: startupQuality
        ) ?? fallbackAutomaticStartupVariant(
            in: variants,
            targetVariant: targetVariant,
            startupQuality: startupQuality
        ) else { return nil }
        guard startupVariant.id != targetVariant.id,
              startupVariant.isPlayable,
              variant(targetVariant, isBetterThan: startupVariant)
        else { return nil }
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "startupQuality selected q\(startupVariant.quality)->q\(targetVariant.quality)"
        )
        return startupVariant
    }

    private func fallbackAutomaticStartupVariant(
        in variants: [PlayVariant],
        targetVariant: PlayVariant,
        startupQuality: Int
    ) -> PlayVariant? {
        let candidates = sortedPlayVariants(variants)
            .filter {
                $0.isPlayable
                    && $0.id != targetVariant.id
                    && $0.quality < targetVariant.quality
                    && $0.dynamicRange == targetVariant.dynamicRange
                    && $0.videoURL != nil
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
            }
        guard !candidates.isEmpty else { return nil }

        let preferredAudioURL = targetVariant.audioURL
        let preferredGroups = [
            candidates.filter {
                $0.audioURL == preferredAudioURL
                    && variantsShareVideoCodecFamily($0, targetVariant)
            },
            candidates.filter { $0.audioURL == preferredAudioURL },
            candidates
        ]
        let preferredQualities = Self.uniqueStartupFallbackQualities(
            startupQuality: startupQuality,
            targetQuality: targetVariant.quality
        )

        for group in preferredGroups where !group.isEmpty {
            for quality in preferredQualities {
                if let candidate = group.first(where: { $0.quality == quality }) {
                    PlayerMetricsLog.record(
                        .qualitySupplement,
                        metricsID: detail.bvid,
                        title: detail.title,
                        message: "startupQuality fallback q\(candidate.quality)->q\(targetVariant.quality)"
                    )
                    return candidate
                }
            }
            if let candidate = group.min(by: { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality < rhs.quality
                }
                return (lhs.bandwidth ?? Int.max) < (rhs.bandwidth ?? Int.max)
            }) {
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: detail.bvid,
                    title: detail.title,
                    message: "startupQuality lowest q\(candidate.quality)->q\(targetVariant.quality)"
                )
                return candidate
            }
        }
        return nil
    }

    private nonisolated static func uniqueStartupFallbackQualities(
        startupQuality: Int,
        targetQuality: Int
    ) -> [Int] {
        var seen = Set<Int>()
        let qualityLadder = [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
        return ([startupQuality, 32, 64, 80, 74, 16, 6] + qualityLadder.reversed())
            .filter { quality in
                quality < targetQuality && seen.insert(quality).inserted
            }
    }

    private func sortedPlayVariants(_ variants: [PlayVariant]) -> [PlayVariant] {
        let shouldPreferEfficientVideo = playbackAdaptationProfile.prefersEnergyEfficientVideo
            || PlaybackEnvironment.current.shouldPreferConservativePlayback
        return variants.sorted { lhs, rhs in
            if lhs.isPlayable != rhs.isPlayable {
                return lhs.isPlayable && !rhs.isPlayable
            }
            if shouldPreferEfficientVideo {
                if lhs.isHardwareDecodingCompatible != rhs.isHardwareDecodingCompatible {
                    return lhs.isHardwareDecodingCompatible && !rhs.isHardwareDecodingCompatible
                }
                let lhsFPS = variantFrameRate(lhs)
                let rhsFPS = variantFrameRate(rhs)
                let lhsIsHighFrameRate = lhsFPS >= 50
                let rhsIsHighFrameRate = rhsFPS >= 50
                if lhsIsHighFrameRate != rhsIsHighFrameRate {
                    return !lhsIsHighFrameRate && rhsIsHighFrameRate
                }
            }
            if lhs.isProgressiveFastStart != rhs.isProgressiveFastStart {
                return !lhs.isProgressiveFastStart && rhs.isProgressiveFastStart
            }
            if lhs.quality != rhs.quality {
                return lhs.quality > rhs.quality
            }
            let lhsFPS = variantFrameRate(lhs)
            let rhsFPS = variantFrameRate(rhs)
            if lhsFPS != rhsFPS {
                return lhsFPS > rhsFPS
            }
            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }
    }

    private func energyEfficientVariant(in variants: [PlayVariant], preferredQuality: Int) -> PlayVariant? {
        let sortedVariants = sortedPlayVariants(variants)
            .filter {
                $0.quality <= preferredQuality
                    && $0.dynamicRange != .dolbyVision
            }
        let hardwareDecoded = sortedVariants.filter(\.isHardwareDecodingCompatible)
        let candidates = hardwareDecoded.isEmpty ? sortedVariants : hardwareDecoded
        if let lowFrameRate = candidates.first(where: { variantFrameRate($0) < 50 }) {
            return lowFrameRate
        }
        return candidates.first
    }

    private func fastStartVariant(for target: PlayVariant?, in variants: [PlayVariant]) -> PlayVariant? {
        guard let target else { return nil }
        if let reason = startupStagedStartupDisabledReason(for: target) {
            logStagedStartupDecision(
                "disabled reason=\(reason) target=q\(target.quality) available=\(Self.qualitySummary(variants))"
            )
            return target
        }
        guard let startup = stagedStartupVariant(for: target, in: variants) else {
            logStagedStartupDecision(
                "disabled reason=noCandidate target=q\(target.quality) available=\(Self.qualitySummary(variants))"
            )
            return target
        }
        logStagedStartupDecision(
            "selected q\(startup.quality)->q\(target.quality) targetFPS=\(Self.formattedFrameRate(variantFrameRate(target))) startupFPS=\(Self.formattedFrameRate(variantFrameRate(startup)))"
        )
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup selected q\(startup.quality)->q\(target.quality)"
        )
        return startup
    }

    private func startupStagedStartupDisabledReason(for targetVariant: PlayVariant) -> String? {
        guard !didSelectPlayVariantManually else { return "manualSelection" }
        guard targetVariant.isPlayable else { return "notPlayable" }
        guard !targetVariant.isProgressiveFastStart else { return "progressive" }
        guard targetVariant.audioURL != nil else { return "noAudio" }
        guard targetVariant.videoStream?.isHardwareDecodingCompatibleVideo == true else { return "unsupportedCodec" }
        guard targetVariant.dynamicRange == .sdr else { return "dynamicRange-\(targetVariant.dynamicRange.rawValue)" }
        guard targetVariant.quality >= 74 else { return "lowTargetQuality" }
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return "conservative" }
        switch environment.networkClass {
        case .wifi, .unknown:
            break
        case .cellular, .constrained:
            return "network-\(environment.networkClass.performanceSampleKey)"
        }
        return nil
    }

    private func stagedStartupVariant(for target: PlayVariant, in variants: [PlayVariant]) -> PlayVariant? {
        guard let targetAudioURL = target.audioURL,
              target.videoURL != nil
        else { return nil }

        let candidates = sortedPlayVariants(variants)
            .filter {
                $0.isPlayable
                    && $0.id != target.id
                    && $0.audioURL == targetAudioURL
                    && $0.quality < target.quality
                    && $0.dynamicRange == target.dynamicRange
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
                    && $0.videoURL != nil
                    && variantsShareVideoCodecFamily($0, target)
            }
        guard !candidates.isEmpty else { return nil }

        let sameFrameRateCandidates = candidates.filter { variantsShareStartupFrameRateClass($0, target) }
        if let candidate = preferredStagedStartupVariant(
            in: sameFrameRateCandidates,
            qualityOrder: stagedStartupQualityOrder(for: target)
        ) {
            return candidate
        }

        guard variantFrameRate(target) >= 50 else {
            return sameFrameRateCandidates.first
        }

        return preferredStagedStartupVariant(
            in: candidates.filter { !variantsShareStartupFrameRateClass($0, target) },
            qualityOrder: stagedStartupQualityOrder(for: target, allowsFrameRateFallback: true)
        )
    }

    private func preferredStagedStartupVariant(
        in candidates: [PlayVariant],
        qualityOrder: [Int]
    ) -> PlayVariant? {
        guard !candidates.isEmpty else { return nil }
        for quality in qualityOrder {
            if let candidate = candidates.first(where: { $0.quality == quality }) {
                return candidate
            }
        }
        return candidates.first
    }

    private func stagedStartupQualityOrder(
        for target: PlayVariant,
        allowsFrameRateFallback: Bool = false
    ) -> [Int] {
        let startupCeiling = adaptiveStartupQualityCeiling ?? Int.max
        func bounded(_ qualities: [Int]) -> [Int] {
            qualities.filter { $0 <= startupCeiling }
        }
        if variantFrameRate(target) >= 50 {
            if allowsFrameRateFallback {
                switch target.quality {
                case 116...:
                    return bounded([80, 64, 32])
                case 74..<116:
                    return bounded([64, 32])
                default:
                    return []
                }
            }
            return target.quality > 74 ? bounded([74]) : []
        }

        switch target.quality {
        case 120...:
            return bounded([112, 80, 64, 32])
        case 112..<120:
            return bounded([80, 64, 32])
        case 80..<112:
            return bounded([64, 32])
        default:
            return []
        }
    }

    private func variantsShareStartupFrameRateClass(_ lhs: PlayVariant, _ rhs: PlayVariant) -> Bool {
        let lhsIsHighFrameRate = variantFrameRate(lhs) >= 50
        let rhsIsHighFrameRate = variantFrameRate(rhs) >= 50
        return lhsIsHighFrameRate == rhsIsHighFrameRate
    }

    private func variantsShareVideoCodecFamily(_ lhs: PlayVariant, _ rhs: PlayVariant) -> Bool {
        guard let lhsCodec = videoCodecFamily(lhs),
              let rhsCodec = videoCodecFamily(rhs)
        else {
            return true
        }
        return lhsCodec == rhsCodec
    }

    private func videoCodecFamily(_ variant: PlayVariant) -> String? {
        if let codecid = variant.videoStream?.codecid {
            switch codecid {
            case 7:
                return "avc"
            case 12:
                return "hevc"
            case 13:
                return "av1"
            default:
                break
            }
        }

        let codec = (variant.videoStream?.codecs ?? variant.codec ?? "").lowercased()
        if codec.contains("avc1") || codec.contains("avc3") {
            return "avc"
        }
        if codec.contains("hvc1") || codec.contains("hev1") || codec.contains("dvh1") || codec.contains("dvhe") {
            return "hevc"
        }
        if codec.contains("av01") {
            return "av1"
        }
        return nil
    }

    private func scheduleFastStartUpgradeIfNeeded(
        from startupVariant: PlayVariant?,
        to targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) {
        fastStartUpgradeTask?.cancel()
        fastStartUpgradeTask = nil
        guard !didSelectPlayVariantManually,
              let cid,
              let startupVariant,
              let targetVariant,
              startupVariant.id != targetVariant.id,
              targetVariant.isPlayable,
              shouldScheduleStagedStartupUpgrade(from: startupVariant, to: targetVariant)
        else { return }

        let startupVariantID = startupVariant.id
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup queued q\(startupVariant.quality)->q\(targetVariant.quality)"
        )
        fastStartUpgradeTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.selectedPlayVariant?.id == startupVariantID
            else { return }

            try? await Task.sleep(nanoseconds: Self.fastStartUpgradeStabilityDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.selectedPlayVariant?.id == startupVariantID
            else {
                self.fastStartUpgradeTask = nil
                return
            }
            guard self.canPerformStagedStartupUpgrade(from: startupVariantID, cid: cid) else {
                self.recordStagedStartupUpgradeSkipped(reason: "unstable", startupVariant: startupVariant, targetVariant: targetVariant)
                self.fastStartUpgradeTask = nil
                return
            }

            let canUpgradeInPlace = self.stablePlayerViewModel?.engineDiagnostics.hlsVideoVariantCount ?? 0 > 1
                && self.canPerformInPlaceHLSVariantUpgrade(from: startupVariant, to: targetVariant)
            let optimizedTarget = canUpgradeInPlace
                ? targetVariant
                : await self.optimizedStartupVariant(targetVariant, source: "fastStartUpgrade") ?? targetVariant
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.selectedPlayVariant?.id == startupVariantID
            else {
                self.fastStartUpgradeTask = nil
                return
            }

            if optimizedTarget.id != targetVariant.id {
                self.playVariants = self.replacingVariant(
                    in: self.playVariants,
                    matching: targetVariant.id,
                    with: optimizedTarget
                )
            }

            let didWarmTarget = await VideoPreloadCenter.shared.warmVariantAndWaitCached(
                optimizedTarget,
                bvid: self.detail.bvid,
                cid: cid,
                page: page,
                delay: 0,
                timeout: Self.fastStartUpgradeWarmupTimeout
            )

            if !didWarmTarget {
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "stagedStartup warmTimeoutContinue q\(startupVariant.quality)->q\(optimizedTarget.quality)"
                )
            }
            guard self.canPerformStagedStartupUpgrade(from: startupVariantID, cid: cid) else {
                let reason = didWarmTarget ? "changedDuringWarmup" : "unstableAfterWarmTimeout"
                self.recordStagedStartupUpgradeSkipped(reason: reason, startupVariant: startupVariant, targetVariant: optimizedTarget)
                self.fastStartUpgradeTask = nil
                return
            }

            if canUpgradeInPlace,
               let playerViewModel = self.stablePlayerViewModel,
               playerViewModel.preferVideoRenditionInCurrentItem(targetVariant) {
                self.selectedPlayVariant = targetVariant
                self.stablePlayerIdentity = self.playerIdentity(for: targetVariant)
                self.observePlaybackErrors(playerViewModel, variant: targetVariant)
                self.playbackFallbackMessage = nil
                self.logSelectedPlayVariant(
                    targetVariant,
                    availableVariants: self.playVariants,
                    source: "fastStartInPlaceUpgrade"
                )
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "stagedStartup inPlace q\(startupVariant.quality)->q\(targetVariant.quality)"
                )
                self.fastStartUpgradeTask = nil
                return
            }

            let resumeTime = self.currentPlaybackResumeTime()
            let shouldResumePlayback = self.currentPlaybackIntent()
            let playbackRate = self.stablePlayerViewModel?.playbackRate ?? .x10
            self.selectedPlayVariant = optimizedTarget
            self.playbackFallbackMessage = nil
            self.logSelectedPlayVariant(
                optimizedTarget,
                availableVariants: self.playVariants,
                source: "fastStartUpgrade"
            )
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: self.detail.bvid,
                title: self.detail.title,
                message: "stagedStartup upgrade q\(startupVariant.quality)->q\(optimizedTarget.quality) at=\(String(format: "%.2fs", resumeTime))"
            )
            self.updateStablePlayerViewModelIfNeeded(
                resumeTimeOverride: resumeTime,
                shouldResumePlayback: shouldResumePlayback,
                playbackRateOverride: playbackRate,
                preservesPreviousPlayerUntilFirstFrame: true
            )
            self.fastStartUpgradeTask = nil
        }
    }

    private func shouldUseStagedStartupVariant(for targetVariant: PlayVariant) -> Bool {
        stagedStartupDisabledReason(for: targetVariant) == nil
    }

    private func stagedStartupDisabledReason(for targetVariant: PlayVariant) -> String? {
        guard !didSelectPlayVariantManually else { return "manualSelection" }
        guard targetVariant.isPlayable else { return "notPlayable" }
        guard !targetVariant.isProgressiveFastStart else { return "progressive" }
        guard targetVariant.audioURL != nil else { return "noAudio" }
        guard targetVariant.videoStream?.isHardwareDecodingCompatibleVideo == true else { return "unsupportedCodec" }
        guard targetVariant.dynamicRange == .sdr else { return "dynamicRange-\(targetVariant.dynamicRange.rawValue)" }
        guard targetVariant.quality >= 74 else { return "lowTargetQuality" }
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return "conservative" }
        switch environment.networkClass {
        case .wifi, .unknown:
            break
        case .cellular, .constrained:
            return "network-\(environment.networkClass.performanceSampleKey)"
        }

        return nil
    }

    private func logStagedStartupDecision(_ message: String) {
        PlayerMetricsLog.logger.info(
            "stagedStartup \(message, privacy: .public) bvid=\(self.detail.bvid, privacy: .public)"
        )
    }

    private nonisolated static func formattedFrameRate(_ frameRate: Double) -> String {
        guard frameRate > 0 else { return "-" }
        return String(format: "%.0f", frameRate)
    }

    private func shouldScheduleStagedStartupUpgrade(from startupVariant: PlayVariant, to targetVariant: PlayVariant) -> Bool {
        guard shouldUseStagedStartupVariant(for: targetVariant),
              startupVariant.isPlayable,
              targetVariant.isPlayable,
              startupVariant.id != targetVariant.id,
              variant(targetVariant, isBetterThan: startupVariant)
        else { return false }
        return true
    }

    private func canPerformStagedStartupUpgrade(from startupVariantID: String, cid: Int) -> Bool {
        guard !isPlaybackInvalidatedForNavigation,
              !didSelectPlayVariantManually,
              selectedCID == cid,
              selectedPlayVariant?.id == startupVariantID,
              !isSwitchingPlayQuality,
              playVariantSwitchTask == nil,
              let player = stablePlayerViewModel,
              player.hasPresentedPlayback,
              player.errorMessage == nil,
              !player.isBuffering,
              !player.isUserSeeking,
              !player.isPictureInPictureActive
        else { return false }
        if let lastUserSeekAt,
           Date().timeIntervalSince(lastUserSeekAt) < Self.fastStartUpgradeSeekCooldown {
            return false
        }
        if let playerLastUserSeekAt = player.lastUserSeekAt,
           Date().timeIntervalSince(playerLastUserSeekAt) < Self.fastStartUpgradeSeekCooldown {
            return false
        }
        return player.isPlaying || player.wantsAutoplay || currentPlaybackIntent()
    }

    private func canPerformInPlaceHLSVariantUpgrade(from startupVariant: PlayVariant, to targetVariant: PlayVariant) -> Bool {
        guard startupVariant.audioURL != nil,
              startupVariant.audioURL == targetVariant.audioURL,
              let targetVideoURL = targetVariant.videoURL
        else { return false }
        return hlsAlternateVideoRenditions(for: startupVariant)
            .contains { $0.videoURL == targetVideoURL }
    }

    private func recordStagedStartupUpgradeSkipped(
        reason: String,
        startupVariant: PlayVariant,
        targetVariant: PlayVariant
    ) {
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup skip reason=\(reason) q\(startupVariant.quality)->q\(targetVariant.quality)"
        )
    }

    private func warmSelectedVariantAfterFirstFrameIfNeeded(_ variant: PlayVariant?, cid: Int?, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              let cid,
              let variant,
              !variant.isProgressiveFastStart
        else { return }
        let canWarmAfterFirstFrame = playbackAdaptationProfile.shouldWarmSupplementalVariants
            || libraryStore.preferredVideoQuality != nil
        guard canWarmAfterFirstFrame else { return }
        let variantID = variant.id
        Task(priority: .utility) { [weak self, variant] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.selectedPlayVariant?.id == variantID
            else { return }
            await VideoPreloadCenter.shared.warmVariant(
                variant,
                bvid: self.detail.bvid,
                cid: cid,
                page: page,
                delay: 0.25
            )
        }
    }

    private func rankPlaybackCDNCandidatesAfterFirstFrameIfNeeded(_ variant: PlayVariant?, cid: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              libraryStore.isPlaybackAutoOptimizationEnabled,
              libraryStore.playbackCDNPreference == .automatic,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback,
              let cid,
              let variant,
              variant.isPlayable
        else { return }
        let hasVideoCandidates = (variant.videoStream?.backupPlayURLs.isEmpty == false)
        let hasAudioCandidates = (variant.audioStream?.backupPlayURLs.isEmpty == false)
        guard hasVideoCandidates || hasAudioCandidates else { return }

        let variantID = variant.id
        Task(priority: .utility) { [weak self, variant] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.selectedPlayVariant?.id == variantID
            else { return }

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid
            else { return }

            let cdnPreference = self.libraryStore.effectivePlaybackCDNPreference
            let headers = BiliHLSManifestBuilder.httpHeaders(
                referer: "https://www.bilibili.com/video/\(self.detail.bvid)"
            )
            await PlayerMetricsLog.withSignpostedInterval(
                "VideoDetailCDNRanking",
                message: "bvid=\(self.detail.bvid) q=\(variant.quality)"
            ) {
                await PlaybackStartupURLProbeService.rankVariantCandidates(
                    for: variant,
                    cdnPreference: cdnPreference,
                    headers: headers
                )
            }
        }
    }

    private func scheduleHLSRenditionPrebuildAfterFirstFrameIfNeeded(
        startupVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) {
        hlsRenditionPrebuildTask?.cancel()
        hlsRenditionPrebuildTask = nil
        guard !isPlaybackInvalidatedForNavigation,
              let cid,
              let startupVariant,
              startupVariant.audioURL != nil,
              hlsRenditionPrebuildLimit > 0
        else { return }
        let candidates = hlsRenditionPrebuildCandidates(
            startupVariant: startupVariant,
            targetVariant: targetVariant
        )
        guard !candidates.isEmpty else { return }
        let candidateSummary = Self.hlsQualitySummary(candidates.map(\.quality))
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: detail.bvid,
            title: detail.title,
            message: "prebuildQueued=\(candidateSummary)"
        )
        hlsRenditionPrebuildTask = Task(priority: .utility) { [weak self, candidates] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid
            else {
                self.hlsRenditionPrebuildTask = nil
                return
            }
            try? await Task.sleep(nanoseconds: Self.hlsRenditionPrebuildDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.stablePlayerViewModel != nil
            else {
                self.hlsRenditionPrebuildTask = nil
                return
            }
            let playbackTime = self.currentPlaybackResumeTime()
            for (index, candidate) in candidates.enumerated() {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.stablePlayerViewModel?.isBuffering != true
                else { break }
                if index > 0 {
                    try? await Task.sleep(nanoseconds: Self.hlsRenditionPrebuildStepNanoseconds)
                }
                let didWarm: Bool
                if playbackTime > 0.25 {
                    didWarm = await VideoPreloadCenter.shared.warmVariantAroundSeek(
                        candidate,
                        bvid: self.detail.bvid,
                        cid: cid,
                        page: page,
                        playbackTime: playbackTime,
                        timeout: Self.hlsRenditionPrebuildTimeout
                    )
                } else {
                    didWarm = await VideoPreloadCenter.shared.warmVariantAndWaitCached(
                        candidate,
                        bvid: self.detail.bvid,
                        cid: cid,
                        page: page,
                        delay: 0,
                        timeout: Self.hlsRenditionPrebuildTimeout
                    )
                }
                PlayerMetricsLog.record(
                    .manifestStage,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "prebuild q\(candidate.quality)=\(didWarm ? "ready" : "skip")"
                )
            }
            self.hlsRenditionPrebuildTask = nil
        }
    }

    private var hlsRenditionPrebuildLimit: Int {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return 0 }
        switch environment.networkClass {
        case .wifi:
            return 2
        case .unknown:
            return 1
        case .cellular, .constrained:
            return 0
        }
    }

    private func hlsRenditionPrebuildCandidates(
        startupVariant: PlayVariant,
        targetVariant: PlayVariant?
    ) -> [PlayVariant] {
        let limit = hlsRenditionPrebuildLimit
        guard limit > 0,
              let startupAudioURL = startupVariant.audioURL
        else { return [] }
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != startupVariant.id
                    && $0.audioURL == startupAudioURL
                    && $0.dynamicRange != .dolbyVision
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
                    && $0.videoURL != nil
            }
        guard !candidates.isEmpty else { return [] }
        var selected = [PlayVariant]()
        var seen = Set<String>()
        func append(_ variant: PlayVariant?) {
            guard selected.count < limit,
                  let variant,
                  seen.insert(variant.id).inserted
            else { return }
            selected.append(variant)
        }
        append(candidates.first { $0.id == targetVariant?.id })
        let targetQuality = targetVariant?.quality ?? startupVariant.quality
        for quality in hlsManualSwitchWarmupQualityOrder(targetQuality: targetQuality) {
            append(candidates.first { $0.quality == quality })
        }
        for candidate in candidates {
            append(candidate)
        }
        return selected
    }

    private func warmLikelySupplementalVariantAfterFirstFrame(cid: Int, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              playbackAdaptationProfile.shouldWarmSupplementalVariants,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }
        let variants = supplementalWarmupVariants()
        guard !variants.isEmpty else { return }
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard !self.isPlaybackInvalidatedForNavigation else { return }
            guard didPresentPlayback else { return }
            for (index, variant) in variants.prefix(1).enumerated() {
                guard !self.isPlaybackInvalidatedForNavigation else { return }
                await VideoPreloadCenter.shared.warmVariant(
                    variant,
                    bvid: self.detail.bvid,
                    cid: cid,
                    page: page,
                    delay: index == 0 ? 0 : 0.45
                )
            }
        }
    }

    private func supplementalWarmupVariants() -> [PlayVariant] {
        let selectedVariantID = selectedPlayVariant?.id
        var result = [PlayVariant]()

        func append(_ variant: PlayVariant?) {
            guard let variant,
                  variant.id != selectedVariantID,
                  !result.contains(where: { $0.id == variant.id })
            else { return }
            result.append(variant)
        }

        append(likelySupplementalWarmupVariant())
        append(dolbyVisionWarmupVariant())
        return result
    }

    private func likelySupplementalWarmupVariant() -> PlayVariant? {
        let playableVariants = playVariants.filter(\.isPlayable)
        var preferredWarmupQualities = [Int]()
        if let preferredQuality = libraryStore.preferredVideoQuality {
            preferredWarmupQualities.append(preferredQuality)
        }
        preferredWarmupQualities += [116, 112, 120, 80, 74]
        for quality in preferredWarmupQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality && !$0.isProgressiveFastStart }) {
                return variant
            }
        }
        return playableVariants
            .filter { !$0.isProgressiveFastStart }
            .max(by: { $0.quality < $1.quality })
    }

    private func dolbyVisionWarmupVariant() -> PlayVariant? {
        sortedPlayVariants(playVariants)
            .first {
                $0.isPlayable
                    && !$0.isProgressiveFastStart
                    && $0.dynamicRange == .dolbyVision
            }
    }

    private func loadUploaderProfile() async {
        guard let mid = detail.owner?.mid, mid > 0 else {
            uploaderProfile = nil
            interactionState.isFollowing = false
            return
        }

        do {
            let profile = try await api.fetchUploaderProfile(mid: mid)
            uploaderProfile = profile
            interactionState.isFollowing = profile.following == true
        } catch {
            uploaderProfile = nil
            interactionState.isFollowing = false
        }
    }

    private func loadInteractionState() async {
        guard let aid = detail.aid else { return }
        do {
            var state = try await api.fetchVideoInteractionState(aid: aid)
            state.isFollowing = uploaderProfile?.following == true
            interactionState = state
            if state.isFavorited {
                Task { await loadFavoriteFoldersForCurrentVideo() }
            }
            interactionMessage = nil
        } catch BiliAPIError.missingSESSDATA {
            interactionState.isFollowing = uploaderProfile?.following == true
        } catch {
            interactionMessage = "互动状态同步失败：\(error.localizedDescription)"
        }
    }

    private func loadRelated(forceRefresh: Bool = false) async {
        guard !relatedState.isLoading else { return }
        guard related.isEmpty || forceRefresh else {
            await refreshRelatedInBackgroundIfNeeded()
            return
        }
        let bvid = detail.bvid
        let timeout = adaptiveRelatedLoadTimeoutNanoseconds
        if !forceRefresh,
           let cached = await VideoPreloadCenter.shared.cachedRelatedVideos(
            for: bvid,
            limit: Self.relatedRecommendationsLimit
           ) {
            related = cached
            relatedState = .loaded
            relatedElapsedMilliseconds = 0
            lastRelatedLoadTimedOut = false
            scheduleRelatedPlaybackPreloadIfAppropriate(for: cached)
            guard cached.count < Self.minimumExpandedRelatedCount else {
                await refreshRelatedInBackgroundIfNeeded()
                return
            }
            relatedState = .loading
        } else {
            relatedState = .loading
            lastRelatedLoadTimedOut = false
            relatedLoadStartTime = CACurrentMediaTime()
            relatedElapsedMilliseconds = nil
        }

        relatedLoadStartTime = CACurrentMediaTime()
        lastRelatedLoadTimedOut = false
        relatedElapsedMilliseconds = nil
        defer {
            if related.isEmpty, relatedState.isLoading {
                relatedState = .idle
            }
        }
        do {
            let videos = try await fetchRelatedWithTimeout(
                bvid: bvid,
                timeout: timeout,
                forceRefresh: true
            )
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return }
            applyLoadedRelatedVideos(videos)
            if !related.isEmpty, relatedState.isLoading {
                relatedState = .loaded
            }
            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
        } catch VideoDetailLoadTimeoutError.related {
            guard !Task.isCancelled else { return }
            if !related.isEmpty {
                relatedState = .loaded
                relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
                return
            }
            if await applyRelatedFallbackIfAvailable(reason: "相关推荐加载超时") {
                relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
                return
            }
            lastRelatedLoadTimedOut = true
            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
            relatedState = .failed("相关推荐加载超时")
        } catch {
            guard !Task.isCancelled else { return }
            if !related.isEmpty {
                relatedState = .loaded
                relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
                return
            }
            if await applyRelatedFallbackIfAvailable(reason: error.localizedDescription) {
                relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
                return
            }
            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
            relatedState = .failed(error.localizedDescription)
        }
    }

    private func refreshRelatedInBackgroundIfNeeded() async {
        guard relatedRefreshTask == nil,
              !isPlaybackInvalidatedForNavigation,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }
        let bvid = detail.bvid
        relatedRefreshTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            defer {
                self.relatedRefreshTask = nil
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
            do {
                let videos = try await VideoPreloadCenter.shared.refreshRelatedVideos(
                    for: bvid,
                    api: self.api,
                    priority: .background,
                    limit: Self.relatedRecommendationsLimit
                )
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid
                else { return }
                if !videos.isEmpty {
                    self.applyLoadedRelatedVideos(videos)
                }
            } catch {
                guard !Task.isCancelled else { return }
                if self.related.isEmpty {
                    _ = await self.applyRelatedFallbackIfAvailable(reason: error.localizedDescription)
                }
            }
        }
    }

    private func fetchRelatedWithTimeout(
        bvid: String,
        timeout: UInt64,
        forceRefresh: Bool = false
    ) async throws -> [VideoItem] {
        try await withThrowingTaskGroup(of: [VideoItem].self) { group -> [VideoItem] in
            group.addTask(priority: forceRefresh ? .utility : .background) { [api] in
                if forceRefresh {
                    return try await VideoPreloadCenter.shared.refreshRelatedVideos(
                        for: bvid,
                        api: api,
                        priority: .utility,
                        limit: Self.relatedRecommendationsLimit
                    )
                }
                return try await VideoPreloadCenter.shared.relatedVideos(
                    for: bvid,
                    api: api,
                    priority: .background,
                    limit: Self.relatedRecommendationsLimit
                )
            }
            group.addTask(priority: .background) { () -> [VideoItem] in
                try await Task.sleep(nanoseconds: timeout)
                throw VideoDetailLoadTimeoutError.related
            }
            guard let result = try await group.next() else { return [] }
            group.cancelAll()
            return result
        }
    }

    private func applyLoadedRelatedVideos(_ videos: [VideoItem]) {
        let filtered = Array(videos
            .filter { $0.bvid != detail.bvid }
            .prefix(Self.relatedRecommendationsLimit))
        guard !filtered.isEmpty || related.isEmpty else { return }
        related = filtered
        lastRelatedLoadTimedOut = false
        relatedState = filtered.isEmpty ? .failed("暂无相关推荐") : .loaded
        if !filtered.isEmpty {
            prefetchRelatedArtwork(filtered)
            scheduleRelatedPlaybackPreloadIfAppropriate(for: filtered)
        }
    }

    @discardableResult
    private func applyRelatedFallbackIfAvailable(reason: String) async -> Bool {
        let fallback = await VideoPreloadCenter.shared.fallbackRelatedVideos(
            excluding: detail.bvid,
            limit: Self.relatedRecommendationsLimit
        )
        guard !fallback.isEmpty else { return false }
        related = fallback
        lastRelatedLoadTimedOut = reason.localizedCaseInsensitiveContains("超时")
        relatedState = .loaded
        prefetchRelatedArtwork(fallback)
        scheduleRelatedPlaybackPreloadIfAppropriate(for: fallback)
        return true
    }

    private func prefetchRelatedArtwork(_ videos: [VideoItem]) {
        let usesCompactArtwork = shouldUseCompactRelatedArtwork
        let prefetchLimit = usesCompactArtwork ? 2 : 3
        let width = usesCompactArtwork ? 300 : 360
        let height = Int((Double(width) * 9.0 / 16.0).rounded())
        let targetPixelSize = usesCompactArtwork ? 300 : 360
        let sources = videos.prefix(prefetchLimit).compactMap { video -> RemoteImageSource? in
            guard let pic = video.pic?.normalizedBiliURL(),
                  let url = URL(string: pic.biliCoverThumbnailURL(width: width, height: height))
            else { return nil }
            return RemoteImageSource(url: url, fallbackURL: URL(string: pic))
        }
        guard !sources.isEmpty else { return }
        relatedArtworkPrefetchTask?.cancel()
        relatedArtworkPrefetchTask = Task(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled, self?.isPlaybackInvalidatedForNavigation != true else { return }
            await RemoteImageCache.shared.prefetch(
                sources,
                targetPixelSize: targetPixelSize,
                maximumConcurrentLoads: usesCompactArtwork ? 1 : 2
            )
            await MainActor.run {
                self?.relatedArtworkPrefetchTask = nil
            }
        }
    }

    private func scheduleRelatedLoadIfNeeded() {
        scheduleRelatedLoadAfterPlaybackStartIfNeeded()
    }

    private func scheduleRelatedLoadAfterPlaybackStartIfNeeded() {
        guard related.isEmpty, !relatedState.isLoading, relatedLoadingTask == nil else { return }
        relatedLoadingTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.relatedLoadingTask = nil
            }
            guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: true),
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation
            else { return }
            if case .firstFrame = release, self.playbackAdaptationProfile.shouldThrottleBackgroundPreload {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
            }
            await self.loadRelated()
            self.scheduleDanmakuLoadIfNeeded()
        }
    }

    private func scheduleDanmakuLoadIfNeeded(force: Bool = false) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard let cid = selectedCID else {
            resetDanmakuLoad(clearItems: true)
            return
        }
        guard isDanmakuEnabled else {
            resetDanmakuLoad(clearItems: true)
            return
        }
        let playbackTime = stablePlayerViewModel?.currentTime ?? 0
        scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: cid, around: playbackTime, force: force)
    }

    func updateDanmakuPlaybackTime(_ playbackTime: TimeInterval, underLoad: Bool = false) {
        guard !isPlaybackInvalidatedForNavigation,
              isDanmakuEnabled,
              let cid = selectedCID
        else { return }
        isDanmakuUnderPlaybackLoad = underLoad
        scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: cid, around: playbackTime, force: false)
    }

    private func scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: Int, around playbackTime: TimeInterval, force: Bool) {
        guard stablePlayerViewModel?.hasPresentedPlayback != true else {
            scheduleDanmakuSegments(cid: cid, around: playbackTime, force: force)
            return
        }

        if force {
            resetDanmakuLoad(clearItems: true)
        }
        danmakuStartupLoadTask?.cancel()
        let token = UUID()
        danmakuStartupLoadToken = token
        danmakuStartupLoadTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.clearDanmakuStartupLoadTaskIfCurrent(token)
            }
            guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: false),
                  case .firstFrame = release,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.isDanmakuEnabled
            else { return }
            let currentPlaybackTime = self.stablePlayerViewModel?.currentTime ?? playbackTime
            self.scheduleDanmakuSegments(cid: cid, around: currentPlaybackTime, force: false)
        }
    }

    private func scheduleDanmakuSegments(cid: Int, around playbackTime: TimeInterval, force: Bool) {
        if force {
            resetDanmakuLoad(clearItems: true)
        }
        guard !didFallbackToFullDanmakuLoad else { return }

        let currentSegment = danmakuSegmentIndex(for: playbackTime)
        let scheduleKey = danmakuScheduleKey(cid: cid, playbackTime: playbackTime, segmentIndex: currentSegment)
        guard force || scheduleKey != lastDanmakuScheduleKey else {
            if danmakuSegmentTasks.isEmpty, danmakuState.isLoading {
                danmakuState = .loaded
            }
            return
        }
        lastDanmakuScheduleKey = scheduleKey

        trimRetainedDanmakuSegments(around: currentSegment)
        let segments = danmakuSegmentsToLoad(around: playbackTime)
            .filter { segment in
                !loadedDanmakuSegments.contains(segment)
                    && !loadingDanmakuSegments.contains(segment)
                    && danmakuSegmentTasks[segment] == nil
            }

        guard !segments.isEmpty else {
            if danmakuSegmentTasks.isEmpty, danmakuState.isLoading {
                danmakuState = .loaded
            }
            return
        }

        if danmakuItems.isEmpty {
            danmakuState = .loading
        }
        for segment in segments {
            loadDanmakuSegment(cid: cid, segmentIndex: segment)
        }
    }

    private func loadDanmakuSegment(cid: Int, segmentIndex: Int) {
        loadingDanmakuSegments.insert(segmentIndex)
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.loadingDanmakuSegments.remove(segmentIndex)
                self.danmakuSegmentTasks[segmentIndex] = nil
                if self.danmakuSegmentTasks.isEmpty, self.danmakuTask == nil, self.danmakuState.isLoading {
                    self.danmakuState = .loaded
                }
            }

            do {
                let items = try await self.api.fetchDanmakuSegment(cid: cid, segmentIndex: segmentIndex)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.isDanmakuEnabled,
                      !self.didFallbackToFullDanmakuLoad
                else { return }

                self.loadedDanmakuSegments.insert(segmentIndex)
                self.danmakuSegmentItems[segmentIndex] = self.sortedDanmakuItems(items)
                self.refreshDanmakuItemsFromSegments()
                self.danmakuState = .loaded
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.isDanmakuEnabled
                else { return }

                if segmentIndex == 1, self.danmakuItems.isEmpty, !self.didFallbackToFullDanmakuLoad {
                    await self.loadFullDanmakuFallback(cid: cid)
                } else if self.loadedDanmakuSegments.isEmpty,
                          self.danmakuItems.isEmpty,
                          self.danmakuSegmentTasks.count <= 1 {
                    self.danmakuState = .failed(error.localizedDescription)
                }
            }
        }
        danmakuSegmentTasks[segmentIndex] = task
    }

    private func loadFullDanmakuFallback(cid: Int) async {
        didFallbackToFullDanmakuLoad = true
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        danmakuSegmentTasks.removeAll()
        loadingDanmakuSegments.removeAll()
        loadedDanmakuSegments.removeAll()
        danmakuSegmentItems.removeAll()
        danmakuTask?.cancel()
        danmakuState = .loading

        danmakuTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.api.fetchDanmaku(cid: cid)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.isDanmakuEnabled
                else { return }
                self.updateDanmakuItems(self.sortedDanmakuItems(items))
                self.danmakuState = .loaded
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid
                else { return }
                self.updateDanmakuItems([])
                self.danmakuState = .failed(error.localizedDescription)
            }
            self.danmakuTask = nil
        }
    }

    private func resetDanmakuLoad(clearItems: Bool) {
        danmakuStartupLoadTask?.cancel()
        danmakuStartupLoadTask = nil
        danmakuStartupLoadToken = nil
        danmakuTask?.cancel()
        danmakuTask = nil
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        danmakuSegmentTasks.removeAll()
        loadedDanmakuSegments.removeAll()
        loadingDanmakuSegments.removeAll()
        danmakuSegmentItems.removeAll()
        didFallbackToFullDanmakuLoad = false
        lastDanmakuScheduleKey = nil
        isDanmakuUnderPlaybackLoad = false
        if clearItems {
            updateDanmakuItems([])
        }
        danmakuState = .idle
    }

    private func refreshDanmakuItemsFromSegments() {
        var seen = Set<String>()
        var merged = [DanmakuItem]()
        let segments = danmakuSegmentItems.keys.sorted()
        let totalItemCount = segments.reduce(0) { count, segment in
            count + (danmakuSegmentItems[segment]?.count ?? 0)
        }
        merged.reserveCapacity(totalItemCount)
        var previousItem: DanmakuItem?
        var isAlreadySorted = true

        for segment in segments {
            for item in danmakuSegmentItems[segment] ?? [] where seen.insert(item.id).inserted {
                if let previousItem,
                   item.time < previousItem.time || (item.time == previousItem.time && item.id < previousItem.id) {
                    isAlreadySorted = false
                }
                merged.append(item)
                previousItem = item
            }
        }
        updateDanmakuItems(isAlreadySorted ? merged : sortedDanmakuItems(merged))
    }

    private func updateDanmakuItems(_ items: [DanmakuItem]) {
        danmakuItems = items
        danmakuItemsRevision &+= 1
        syncDanmakuRenderStore()
    }

    private func sortedDanmakuItems(_ items: [DanmakuItem]) -> [DanmakuItem] {
        items.sorted { lhs, rhs in
            if lhs.time != rhs.time {
                return lhs.time < rhs.time
            }
            return lhs.id < rhs.id
        }
    }

    private func danmakuSegmentsToLoad(around playbackTime: TimeInterval) -> [Int] {
        let current = danmakuSegmentIndex(for: playbackTime)
        var segments = [current]
        guard !isDanmakuUnderPlaybackLoad else {
            return boundedDanmakuSegments(segments)
        }
        if !shouldThrottleDanmakuSegmentPrefetch {
            segments.append(current + 1)
        }
        let offset = playbackTime - TimeInterval(current - 1) * Self.danmakuSegmentDuration
        if current > 1, offset < 18, !shouldThrottleDanmakuSegmentPrefetch {
            segments.insert(current - 1, at: 0)
        }
        return boundedDanmakuSegments(segments)
    }

    private var shouldThrottleDanmakuSegmentPrefetch: Bool {
        isDanmakuUnderPlaybackLoad
            || PlaybackEnvironment.current.shouldPreferConservativePlayback
            || playbackAdaptationProfile.shouldThrottleBackgroundPreload
            || effectiveDanmakuSettings.loadFactor < 0.72
    }

    private func boundedDanmakuSegments(_ segments: [Int]) -> [Int] {
        var bounded = Array(Set(segments.filter { $0 >= 1 })).sorted()
        if let maxSegment = maxDanmakuSegmentIndex {
            bounded = bounded.filter { $0 <= maxSegment }
        }
        return bounded
    }

    private func trimRetainedDanmakuSegments(around segmentIndex: Int) {
        guard !danmakuSegmentItems.isEmpty else { return }
        let retainedRange = isDanmakuUnderPlaybackLoad
            ? max(1, segmentIndex - 1)...(segmentIndex + 1)
            : max(1, segmentIndex - 2)...(segmentIndex + 3)
        let removableSegments = danmakuSegmentItems.keys.filter { !retainedRange.contains($0) }
        guard !removableSegments.isEmpty else { return }
        removableSegments.forEach { danmakuSegmentItems[$0] = nil }
        refreshDanmakuItemsFromSegments()
    }

    private func danmakuSegmentIndex(for playbackTime: TimeInterval) -> Int {
        max(1, Int(max(0, playbackTime) / Self.danmakuSegmentDuration) + 1)
    }

    private func danmakuScheduleKey(cid: Int, playbackTime: TimeInterval, segmentIndex: Int) -> DanmakuScheduleKey {
        let segmentStart = TimeInterval(segmentIndex - 1) * Self.danmakuSegmentDuration
        let secondsIntoSegment = max(0, playbackTime - segmentStart)
        let isNearPreviousBoundary = segmentIndex > 1 && secondsIntoSegment < 18
        return DanmakuScheduleKey(
            cid: cid,
            segmentIndex: segmentIndex,
            includesPreviousSegment: isNearPreviousBoundary
        )
    }

    private var maxDanmakuSegmentIndex: Int? {
        guard let duration = detail.duration, duration > 0 else { return nil }
        return max(1, Int(ceil(Double(duration) / Self.danmakuSegmentDuration)))
    }

    private func waitForFirstFrameOrFailure() async -> Bool {
        await waitForPlaybackStartupRelease(acceptsFailure: false) == .firstFrame
    }

    private func waitForPlaybackStartupRelease(acceptsFailure: Bool) async -> PlaybackStartupRelease? {
        guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return nil }
        if stablePlayerViewModel?.hasPresentedPlayback == true || playbackStartupRelease == .firstFrame {
            return .firstFrame
        }
        if stablePlayerViewModel?.errorMessage != nil || isPlayURLFailed {
            return acceptsFailure ? .failed : nil
        }
        if let release = playbackStartupRelease {
            switch release {
            case .firstFrame:
                return .firstFrame
            case .failed:
                return acceptsFailure ? .failed : nil
            }
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else {
                    continuation.resume(returning: nil)
                    return
                }
                if stablePlayerViewModel?.hasPresentedPlayback == true || playbackStartupRelease == .firstFrame {
                    continuation.resume(returning: .firstFrame)
                    return
                }
                if stablePlayerViewModel?.errorMessage != nil || isPlayURLFailed {
                    continuation.resume(returning: acceptsFailure ? .failed : nil)
                    return
                }
                playbackStartupWaiters[waiterID] = PlaybackStartupWaiter(
                    acceptsFailure: acceptsFailure,
                    continuation: continuation
                )
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelPlaybackStartupWaiter(waiterID)
            }
        }
    }

    private var isPlayURLFailed: Bool {
        if case .failed = playURLState {
            return true
        }
        return false
    }

    private var adaptiveRelatedLoadTimeoutNanoseconds: UInt64 {
        let environment = PlaybackEnvironment.current
        if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            return 2_200_000_000
        }
        switch environment.networkClass {
        case .wifi, .unknown:
            return min(relatedLoadTimeoutNanoseconds, 3_200_000_000)
        case .cellular, .constrained:
            return 2_400_000_000
        }
    }

    private func scheduleRelatedPlaybackPreloadIfAppropriate(for _: [VideoItem]) {
        relatedPreloadTask?.cancel()
        relatedPreloadTask = nil
    }

    private func scheduleRelatedPlaybackPreloadAfterFirstFrame(for videos: [VideoItem]) {
        relatedPreloadTask?.cancel()
        let environment = PlaybackEnvironment.current
        let candidateLimit = RelatedPlaybackPrefetchPolicy.candidateLimit(
            environment: environment,
            backgroundPreloadLimit: playbackAdaptationProfile.backgroundPreloadLimit,
            isPlaying: true,
            isBuffering: false
        )
        guard candidateLimit > 0 else {
            relatedPreloadTask = nil
            return
        }
        let candidates = Array(videos
            .filter { $0.cid != nil && $0.bvid != detail.bvid }
            .prefix(candidateLimit))
        guard !candidates.isEmpty else {
            relatedPreloadTask = nil
            return
        }
        relatedPreloadTask = Task(priority: .background) { [weak self, api] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback else {
                self.relatedPreloadTask = nil
                return
            }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            for video in candidates {
                guard !Task.isCancelled,
                      PlaybackEnvironment.current.networkClass == .wifi,
                      self.stablePlayerViewModel?.isPlaying == true,
                      self.stablePlayerViewModel?.isBuffering == false
                else { return }
                let preferredQuality = self.libraryStore.preferredVideoQuality
                let playbackAdaptationProfile = self.playbackAdaptationProfile
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: self.libraryStore.effectivePlaybackCDNPreference,
                    priority: .background,
                    warmsMedia: false,
                    mediaWarmupDelay: 0,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
            }
        }
    }

    private func loadInitialComments() async {
        guard detail.aid != nil else {
            if comments.isEmpty {
                commentState = .idle
            }
            return
        }
        commentCursor = ""
        commentsEnd = false
        comments = []
        didCompleteInitialCommentLoad = false
        await loadCommentsPage()
    }

    private func loadCommentsPage() async {
        guard let aid = detail.aid else {
            if comments.isEmpty {
                commentState = .idle
            }
            return
        }
        let isInitialPage = comments.isEmpty && commentCursor.isEmpty
        commentState = .loading
        do {
            let page = try await fetchCommentsWithTimeout(aid: aid, cursor: commentCursor, sort: selectedCommentSort)
            guard !Task.isCancelled else {
                resetCommentStateAfterCancellation(isInitialPage: isInitialPage)
                return
            }
            let pageComments = comments.isEmpty
                ? (page.topReplies ?? []) + (page.replies ?? [])
                : (page.replies ?? [])
            appendUniqueComments(filteredComments(pageComments))
            commentCursor = page.cursor?.next ?? ""
            commentsEnd = page.cursor?.isEnd ?? true
            if isInitialPage {
                didCompleteInitialCommentLoad = true
            }
            commentState = .loaded
        } catch is CancellationError {
            resetCommentStateAfterCancellation(isInitialPage: isInitialPage)
        } catch {
            guard !Task.isCancelled else { return }
            commentState = .failed(error.localizedDescription)
        }
    }

    private func resetCommentStateAfterCancellation(isInitialPage: Bool) {
        if comments.isEmpty, isInitialPage, !didCompleteInitialCommentLoad {
            commentState = .idle
        } else {
            commentState = .loaded
        }
    }

    private func fetchCommentsWithTimeout(aid: Int, cursor: String, sort: CommentSort) async throws -> CommentPage {
        try await withThrowingTaskGroup(of: CommentPage.self) { group in
            group.addTask(priority: .userInitiated) {
                try await self.api.fetchComments(aid: aid, cursor: cursor, sort: sort)
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw BiliAPIError.api(code: -1, message: "评论加载超时，请稍后重试")
            }
            guard let page = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return page
        }
    }

    private func loadReplyPage(for comment: Comment, reset: Bool) async {
        guard let aid = detail.aid else {
            replyThreadStates[comment.id] = .failed("没有找到视频 AV 号，无法加载回复")
            return
        }
        replyThreadStates[comment.id] = .loading
        do {
            let nextPage = reset ? 1 : (replyThreadPages[comment.id] ?? 1) + 1
            let page = try await api.fetchCommentReplies(aid: aid, root: comment.rpid, page: nextPage)
            let fetchedReplies = filteredComments(page.replies ?? [])
            let existingReplies = reset
                ? filteredComments(comment.replies ?? [])
                : filteredComments(replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(existingReplies + fetchedReplies)
            replyThreads[comment.id] = replies
            replyThreadPages[comment.id] = nextPage
            let totalCount = comment.replyCount ?? Int.max
            replyThreadHasMore[comment.id] = !fetchedReplies.isEmpty && replies.count < totalCount
            replyThreadStates[comment.id] = .loaded
        } catch {
            if reset {
                replyThreads[comment.id] = filteredComments(comment.replies ?? [])
            }
            replyThreadStates[comment.id] = .failed(error.localizedDescription)
        }
    }

    private func loadDialogPage(for root: Comment, reply: Comment) async {
        guard let aid = detail.aid else {
            dialogThreadStates[dialogKey(root: root, reply: reply)] = .failed("没有找到视频 AV 号，无法加载对话")
            return
        }

        let key = dialogKey(root: root, reply: reply)
        let fallbackReplies = filteredComments(localDialogReplies(root: root, reply: reply))

        guard let dialogID = reply.dialogID, dialogID > 0 else {
            dialogThreads[key] = fallbackReplies
            dialogThreadStates[key] = .loaded
            return
        }

        dialogThreadStates[key] = .loading
        do {
            let page = try await api.fetchCommentDialog(aid: aid, root: root.rpid, dialog: dialogID)
            let replies = uniqueComments(filteredComments(page.replies ?? []) + fallbackReplies)
            dialogThreads[key] = replies.isEmpty ? fallbackReplies : replies
            dialogThreadStates[key] = .loaded
        } catch {
            dialogThreads[key] = fallbackReplies
            dialogThreadStates[key] = .failed(error.localizedDescription)
        }
    }

    private func scheduleSponsorBlockSegmentsAfterFirstFrame() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard libraryStore.sponsorBlockEnabled, let cid = selectedCID else {
            resetSponsorBlockSegments()
            return
        }

        let identity = sponsorBlockIdentity(for: detail.bvid, cid: cid)
        if sponsorBlockIdentity == identity {
            applySponsorBlockSegmentsToPlayer()
            return
        }

        sponsorBlockTask?.cancel()
        sponsorBlockTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.sponsorBlockTask = nil
            }
            guard !self.isPlaybackInvalidatedForNavigation else { return }
            guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: false),
                  case .firstFrame = release,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation
            else { return }
            do {
                let segments = try await self.sponsorBlockService.fetchSkipSegments(bvid: self.detail.bvid, cid: cid)
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = segments
                self.applySponsorBlockSegmentsToPlayer()
            } catch {
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = []
                self.applySponsorBlockSegmentsToPlayer()
            }
        }
    }

    private func resetSponsorBlockSegments() {
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        stablePlayerViewModel?.setSponsorBlockSegments([], isEnabled: false)
    }

    private func applySponsorBlockSegmentsToPlayer() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        stablePlayerViewModel?.setSponsorBlockSegments(
            sponsorBlockSegments,
            isEnabled: libraryStore.sponsorBlockEnabled
        ) { [sponsorBlockService] event in
            await sponsorBlockService.reportViewed(uuid: event.segment.uuid)
        }
    }

    private func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard libraryStore.blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    private func refilterLoadedComments() {
        if libraryStore.blocksGoodsComments {
            comments = filteredComments(comments)
            replyThreads = replyThreads.mapValues(filteredComments)
            dialogThreads = dialogThreads.mapValues(filteredComments)
        } else {
            Task { await reloadCommentRelatedData() }
        }
    }

    private func reloadCommentRelatedData() async {
        await loadInitialComments()
        for root in Array(replyThreads.keys) {
            replyThreads[root] = nil
            replyThreadPages[root] = 0
            replyThreadHasMore[root] = true
        }
        dialogThreads.removeAll()
    }

    private func dialogKey(root: Comment, reply: Comment) -> String {
        VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
    }

    private func localDialogReplies(root: Comment, reply: Comment) -> [Comment] {
        VideoDetailCommentThreadResolver.localDialogReplies(reply, siblings: replies(for: root))
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        VideoDetailCommentThreadResolver.uniqueComments(comments)
    }

    private func refreshInteractionMutationAggregate() {
        let nextValue = isMutatingLike ||
            isMutatingCoin ||
            isMutatingFavorite ||
            isMutatingFollow
        guard isMutatingInteraction != nextValue else { return }
        isMutatingInteraction = nextValue
    }

    private func isInteractionMutationActive(_ kind: InteractionMutationKind) -> Bool {
        switch kind {
        case .like:
            return isMutatingLike
        case .coin:
            return isMutatingCoin
        case .favorite:
            return isMutatingFavorite
        case .follow:
            return isMutatingFollow
        }
    }

    private func setInteractionMutationActive(_ active: Bool, for kind: InteractionMutationKind) {
        switch kind {
        case .like:
            isMutatingLike = active
        case .coin:
            isMutatingCoin = active
        case .favorite:
            isMutatingFavorite = active
        case .follow:
            isMutatingFollow = active
        }
    }

    @discardableResult
    private func performInteractionMutation(
        _ kind: InteractionMutationKind,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isInteractionMutationActive(kind) else { return false }
        setInteractionMutationActive(true, for: kind)
        interactionMessage = nil
        defer { setInteractionMutationActive(false, for: kind) }

        do {
            try await operation()
            await refreshDetailMetadata()
            return true
        } catch {
            interactionMessage = interactionFailureMessage(error)
            return false
        }
    }

    private func recoverLikeStateMismatchIfNeeded(_ error: Error, targetState: Bool) -> Bool {
        guard let biliError = error as? BiliAPIError,
              case .api(let code, _) = biliError,
              code == 65004
        else { return false }

        interactionState.isLiked = targetState
        interactionMessage = nil
        return true
    }

    private func refreshDetailMetadata() async {
        do {
            let updated = try await api.fetchVideoDetail(bvid: detail.bvid)
            detail = updated
            syncCommentsRenderStore()
            if selectedCID == nil {
                selectedCID = updated.pages?.first?.cid ?? updated.cid
            }
        } catch {
            // The interaction already succeeded, so stale stat counts should not block the UI state update.
        }

        await loadUploaderProfile()
        await loadInteractionState()
    }

    private func interactionFailureMessage(_ error: Error) -> String {
        if case BiliAPIError.missingSESSDATA = error {
            return "请先登录后再进行互动操作"
        }
        return error.localizedDescription
    }

    private func elapsedMilliseconds(since startTime: CFTimeInterval?) -> Int? {
        guard let startTime else { return nil }
        return Int(((CACurrentMediaTime() - startTime) * 1000).rounded())
    }

    private func elapsedMilliseconds(since startTime: CFTimeInterval) -> Int {
        Int(((CACurrentMediaTime() - startTime) * 1000).rounded())
    }

    private func formattedMilliseconds(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return formatMilliseconds(value)
    }

    private func formatMilliseconds(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }
}

private enum VideoDetailLoadTimeoutError: Error {
    case playURL
    case related
}

private struct DanmakuScheduleKey: Equatable {
    let cid: Int
    let segmentIndex: Int
    let includesPreviousSegment: Bool
}

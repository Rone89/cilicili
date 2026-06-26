import Foundation

struct VideoDetailViewModelRenderStores {
    let comments = VideoDetailCommentsRenderStore()
    let related = VideoDetailRelatedRenderStore()
    let interaction = VideoDetailInteractionRenderStore()
    let playback = VideoDetailPlaybackRenderStore()
    let commentThread = VideoDetailCommentThreadRenderStore()
    let favoriteFolder = VideoDetailFavoriteFolderRenderStore()
    let danmakuSettings = VideoDetailDanmakuSettingsRenderStore()
    let danmaku = VideoDetailDanmakuRenderStore()
    let networkDiagnostics = VideoDetailNetworkDiagnosticsRenderStore()
    let description = VideoDetailDescriptionRenderStore()
    let playerIdentity = VideoDetailPlayerIdentityRenderStore()
}

extension VideoDetailViewModel {
    var commentsRenderStore: VideoDetailCommentsRenderStore {
        renderStores.comments
    }

    var relatedRenderStore: VideoDetailRelatedRenderStore {
        renderStores.related
    }

    var interactionRenderStore: VideoDetailInteractionRenderStore {
        renderStores.interaction
    }

    var playbackRenderStore: VideoDetailPlaybackRenderStore {
        renderStores.playback
    }

    var commentThreadRenderStore: VideoDetailCommentThreadRenderStore {
        renderStores.commentThread
    }

    var favoriteFolderRenderStore: VideoDetailFavoriteFolderRenderStore {
        renderStores.favoriteFolder
    }

    var danmakuSettingsRenderStore: VideoDetailDanmakuSettingsRenderStore {
        renderStores.danmakuSettings
    }

    var danmakuRenderStore: VideoDetailDanmakuRenderStore {
        renderStores.danmaku
    }

    var networkDiagnosticsRenderStore: VideoDetailNetworkDiagnosticsRenderStore {
        renderStores.networkDiagnostics
    }

    var descriptionRenderStore: VideoDetailDescriptionRenderStore {
        renderStores.description
    }

    var playerIdentityRenderStore: VideoDetailPlayerIdentityRenderStore {
        renderStores.playerIdentity
    }
}

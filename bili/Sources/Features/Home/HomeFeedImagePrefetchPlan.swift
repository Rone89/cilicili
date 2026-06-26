import Foundation

nonisolated struct HomeFeedImagePrefetchPlan {
    let coverSources: [RemoteImageSource]
    let avatarSources: [RemoteImageSource]
    let coverTargetPixelSize: Int
    let avatarTargetPixelSize: Int

    static func make(
        for videos: [VideoItem],
        layout: HomeFeedLayout,
        limit: Int
    ) -> HomeFeedImagePrefetchPlan {
        var seenCovers = Set<String>()
        var seenAvatars = Set<String>()
        var coverSources = [RemoteImageSource]()
        var avatarSources = [RemoteImageSource]()
        let sizes = targetPixelSizes(for: layout)

        for video in videos.prefix(limit) {
            if let source = video.pic?.normalizedBiliURL(),
               let coverSource = homeCoverImageSource(
                source: source,
                layout: layout,
                targetPixelSize: sizes.cover
               ),
               seenCovers.insert(source).inserted {
                coverSources.append(coverSource)
            }
            if let source = video.owner?.face?.normalizedBiliURL(),
               let url = URL(string: source.biliAvatarThumbnailURL(size: sizes.avatar)),
               seenAvatars.insert(source).inserted {
                avatarSources.append(RemoteImageSource(url: url, fallbackURL: URL(string: source)))
            }
        }

        return HomeFeedImagePrefetchPlan(
            coverSources: coverSources,
            avatarSources: avatarSources,
            coverTargetPixelSize: sizes.cover,
            avatarTargetPixelSize: sizes.avatar
        )
    }
}

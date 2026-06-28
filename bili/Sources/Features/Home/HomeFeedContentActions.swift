import SwiftUI

struct HomeFeedContentActions {
    let onVideoSelect: ((VideoItem) -> Void)?
    let onVideoTap: (VideoItem) -> Void
    let onVideoPress: (VideoItem) -> Void
    let onVisibleFrame: (VideoItem, Int) -> Void
    let onInvisibleFrame: (VideoItem) -> Void
    let onLoadMore: (VideoItem) async -> Void
    let onRefreshFromLastSeenMarker: () async -> Void
}

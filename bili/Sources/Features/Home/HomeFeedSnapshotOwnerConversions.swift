import Foundation

extension HomeFeedCachedOwner {
    nonisolated init(owner: VideoOwner) {
        mid = owner.mid
        name = owner.name
        face = owner.face
    }

    nonisolated var videoOwner: VideoOwner {
        VideoOwner(mid: mid, name: name, face: face)
    }
}

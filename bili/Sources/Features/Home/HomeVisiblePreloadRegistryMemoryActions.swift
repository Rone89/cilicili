import SwiftUI

extension HomeVisiblePreloadRegistry {
    mutating func rememberVisiblePreload(_ bvid: String) {
        recentVisiblePreloadVideos.insert(bvid)
        recentVisiblePreloadOrder.removeAll { $0 == bvid }
        recentVisiblePreloadOrder.append(bvid)
        while recentVisiblePreloadOrder.count > recentVisiblePreloadLimit {
            let evicted = recentVisiblePreloadOrder.removeFirst()
            recentVisiblePreloadVideos.remove(evicted)
        }
    }
}

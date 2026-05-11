import Foundation

@MainActor
enum ManualVideoFullscreenSession {
    private(set) static var activeCount = 0
    private static var retainedHosts: [ObjectIdentifier: AnyObject] = [:]

    static var isActive: Bool {
        activeCount > 0
    }

    static func begin(retaining host: AnyObject? = nil) {
        if let host {
            retainedHosts[ObjectIdentifier(host)] = host
            activeCount = retainedHosts.count
        } else {
            activeCount += 1
        }
    }

    static func end(retaining host: AnyObject? = nil) {
        if let host {
            retainedHosts.removeValue(forKey: ObjectIdentifier(host))
            activeCount = retainedHosts.count
        } else {
            activeCount = max(activeCount - 1, 0)
            if activeCount == 0 {
                retainedHosts.removeAll()
            }
        }
    }
}

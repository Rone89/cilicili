import Foundation

@MainActor
enum ManualVideoFullscreenSession {
    private(set) static var activeCount = 0

    static var isActive: Bool {
        activeCount > 0
    }

    static func begin() {
        activeCount += 1
    }

    static func end() {
        activeCount = max(activeCount - 1, 0)
    }
}

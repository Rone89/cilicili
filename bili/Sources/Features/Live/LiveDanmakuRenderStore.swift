import Combine
import Foundation
import SwiftUI

@MainActor
final class LiveDanmakuRenderStore: ObservableObject {
    @Published private(set) var items: [DanmakuItem] = []
    @Published private(set) var itemsRevision = 0
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var isEnabled: Bool
    @Published private(set) var settings: DanmakuSettings
    let diagnosticsStore: LiveDanmakuDiagnosticsStore

    init(
        isEnabled: Bool,
        settings: DanmakuSettings,
        diagnostics: LiveDanmakuDiagnosticSnapshot
    ) {
        self.isEnabled = isEnabled
        self.settings = settings.normalized
        self.diagnosticsStore = LiveDanmakuDiagnosticsStore(snapshot: diagnostics)
    }

    var itemCount: Int {
        items.count
    }

    func updateEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled
    }

    func updateSettings(_ settings: DanmakuSettings) {
        let normalized = settings.normalized
        guard self.settings != normalized else { return }
        self.settings = normalized
    }

    func updatePlaybackTime(_ playbackTime: TimeInterval) {
        let sanitizedTime = max(0, playbackTime)
        guard abs(self.playbackTime - sanitizedTime) >= 0.1 || sanitizedTime == 0 else { return }
        self.playbackTime = sanitizedTime
    }

    func appendItems(_ newItems: [DanmakuItem], retainingLimit limit: Int) {
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        if items.count > limit {
            items.removeFirst(items.count - limit)
        }
        itemsRevision &+= 1
    }

    func clearItems() {
        guard !items.isEmpty else { return }
        items.removeAll()
        itemsRevision &+= 1
    }

    func updateDiagnostics(_ diagnostics: LiveDanmakuDiagnosticSnapshot) {
        diagnosticsStore.update(diagnostics)
    }
}

@MainActor
final class LiveDanmakuDiagnosticsStore: ObservableObject {
    @Published private(set) var snapshot: LiveDanmakuDiagnosticSnapshot

    init(snapshot: LiveDanmakuDiagnosticSnapshot) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: LiveDanmakuDiagnosticSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}

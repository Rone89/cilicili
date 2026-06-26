import Combine
import SwiftUI

struct RootRuntimeSettingsSnapshot: Equatable {
    var appearanceMode: AppAppearanceMode = .system
    var minimizesTabBarOnScroll = true
    var visibleRootTabs: [AppTab] = AppTab.defaultVisibleTabs
}

@MainActor
final class RootRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = RootRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var appearanceMode: AppAppearanceMode { snapshot.appearanceMode }
    var minimizesTabBarOnScroll: Bool { snapshot.minimizesTabBarOnScroll }
    var visibleRootTabs: [AppTab] { snapshot.visibleRootTabs }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = RootRuntimeSettingsSnapshot(
            appearanceMode: libraryStore.appearanceMode,
            minimizesTabBarOnScroll: libraryStore.minimizesTabBarOnScroll,
            visibleRootTabs: libraryStore.visibleRootTabs
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct HomeRuntimeSettingsSnapshot: Equatable {
    var homeFeedLayout: HomeFeedLayout = .singleColumn
    var homeRefreshTriggerDistance: Double = LibraryStore.defaultHomeRefreshTriggerDistance
}

@MainActor
final class HomeRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = HomeRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var homeFeedLayout: HomeFeedLayout { snapshot.homeFeedLayout }
    var homeRefreshTriggerDistance: Double { snapshot.homeRefreshTriggerDistance }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = HomeRuntimeSettingsSnapshot(
            homeFeedLayout: libraryStore.homeFeedLayout,
            homeRefreshTriggerDistance: libraryStore.homeRefreshTriggerDistance
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct PlayerRuntimeSettingsSnapshot: Equatable {
    var defaultPlaybackRate: Double = 1.0
    var incognitoModeEnabled = false
}

@MainActor
final class PlayerRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = PlayerRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var defaultPlaybackRate: Double { snapshot.defaultPlaybackRate }
    var incognitoModeEnabled: Bool { snapshot.incognitoModeEnabled }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = PlayerRuntimeSettingsSnapshot(
            defaultPlaybackRate: libraryStore.defaultPlaybackRate,
            incognitoModeEnabled: libraryStore.incognitoModeEnabled
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct VideoDetailRuntimeSettingsSnapshot: Equatable {
    var playerPerformanceOverlayEnabled = false
    var showsNetworkDiagnosticsButton = false
    var showsPinnedProgressBar = false
    var preferredVideoQuality: Int? = LibraryStore.defaultPreferredVideoQuality
    var effectivePlaybackCDNPreference: PlaybackCDNPreference = .automatic
    var playbackAutoOptimizationEnabled = true
    var minimizesTabBarOnScroll = true
}

@MainActor
final class VideoDetailRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = VideoDetailRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var playerPerformanceOverlayEnabled: Bool { snapshot.playerPerformanceOverlayEnabled }
    var showsNetworkDiagnosticsButton: Bool { snapshot.showsNetworkDiagnosticsButton }
    var showsPinnedProgressBar: Bool { snapshot.showsPinnedProgressBar }
    var preferredVideoQuality: Int? { snapshot.preferredVideoQuality }
    var effectivePlaybackCDNPreference: PlaybackCDNPreference { snapshot.effectivePlaybackCDNPreference }
    var playbackAutoOptimizationEnabled: Bool { snapshot.playbackAutoOptimizationEnabled }
    var minimizesTabBarOnScroll: Bool { snapshot.minimizesTabBarOnScroll }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = VideoDetailRuntimeSettingsSnapshot(
            playerPerformanceOverlayEnabled: libraryStore.playerPerformanceOverlayEnabled,
            showsNetworkDiagnosticsButton: libraryStore.showsVideoDetailNetworkDiagnosticsButton,
            showsPinnedProgressBar: libraryStore.showsVideoDetailPinnedProgressBar,
            preferredVideoQuality: libraryStore.preferredVideoQuality,
            effectivePlaybackCDNPreference: libraryStore.effectivePlaybackCDNPreference,
            playbackAutoOptimizationEnabled: libraryStore.isPlaybackAutoOptimizationEnabled,
            minimizesTabBarOnScroll: libraryStore.minimizesTabBarOnScroll
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct DynamicCommentsRuntimeSettingsSnapshot: Equatable {
    var blocksGoodsComments = true
}

@MainActor
final class DynamicCommentsRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = DynamicCommentsRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var blocksGoodsComments: Bool { snapshot.blocksGoodsComments }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = DynamicCommentsRuntimeSettingsSnapshot(
            blocksGoodsComments: libraryStore.blocksGoodsComments
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

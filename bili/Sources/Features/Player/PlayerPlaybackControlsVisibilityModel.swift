import Combine
import SwiftUI

@MainActor
final class PlayerPlaybackControlsVisibilityModel: ObservableObject {
    @Published var isVisible = true

    private var isAutoHideSuspended = false
    private var autoHideTask: Task<Void, Never>?

    func syncSecondaryControlsPresentation(
        _ isPresented: Bool,
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        isAutoHideSuspended = isPresented
        if isPresented {
            cancelAutoHide()
            show(scheduleAutoHide: false, showsPlaybackControls: showsPlaybackControls)
        } else {
            scheduleAutoHide(
                showsPlaybackControls: showsPlaybackControls,
                isLayoutTransitioning: isLayoutTransitioning
            )
        }
    }

    func showAndSchedule(
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        show(
            scheduleAutoHide: true,
            animated: !isLayoutTransitioning,
            showsPlaybackControls: showsPlaybackControls,
            isLayoutTransitioning: isLayoutTransitioning
        )
    }

    func markInteraction(
        keepsVisible: Bool = false,
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        show(
            scheduleAutoHide: !keepsVisible,
            animated: !isLayoutTransitioning,
            showsPlaybackControls: showsPlaybackControls,
            isLayoutTransitioning: isLayoutTransitioning
        )
        if keepsVisible {
            cancelAutoHide()
        }
    }

    func toggle(
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        guard showsPlaybackControls else { return }
        if isVisible {
            hide(animated: true, duration: 0.18)
        } else {
            showAndSchedule(
                showsPlaybackControls: showsPlaybackControls,
                isLayoutTransitioning: isLayoutTransitioning
            )
        }
    }

    func hide(animated: Bool, duration: TimeInterval) {
        cancelAutoHide()
        let update = { self.isVisible = false }
        if animated {
            withAnimation(.easeInOut(duration: duration), update)
        } else {
            update()
        }
    }

    func show(
        scheduleAutoHide: Bool,
        animated: Bool = true,
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool = false
    ) {
        guard showsPlaybackControls else { return }
        if !isVisible {
            let update = { self.isVisible = true }
            if animated {
                withAnimation(.easeInOut(duration: 0.18), update)
            } else {
                update()
            }
        }
        if scheduleAutoHide {
            self.scheduleAutoHide(
                showsPlaybackControls: showsPlaybackControls,
                isLayoutTransitioning: isLayoutTransitioning
            )
        }
    }

    func scheduleAutoHide(
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        guard showsPlaybackControls, isVisible else { return }
        guard !isLayoutTransitioning else { return }
        guard !isAutoHideSuspended else { return }
        cancelAutoHide()
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.isAutoHideSuspended else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isVisible = false
            }
            self.autoHideTask = nil
        }
    }

    func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    deinit {
        autoHideTask?.cancel()
    }
}

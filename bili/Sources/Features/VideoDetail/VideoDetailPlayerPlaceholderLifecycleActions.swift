import SwiftUI

@MainActor
struct VideoDetailPlayerPlaceholderLifecycleActions {
    private static let slowLoadingDelayNanoseconds: UInt64 = 4_800_000_000

    @Binding var isTakingLong: Bool

    func watchSlowLoadingIfNeeded(_ presentation: VideoDetailPlayerPlaceholderPresentation) async {
        isTakingLong = false
        guard presentation.shouldWatchSlowLoading else { return }

        try? await Task.sleep(nanoseconds: Self.slowLoadingDelayNanoseconds)
        guard !Task.isCancelled, presentation.shouldWatchSlowLoading else { return }

        withAnimation(.smooth(duration: 0.24)) {
            isTakingLong = true
        }
    }
}

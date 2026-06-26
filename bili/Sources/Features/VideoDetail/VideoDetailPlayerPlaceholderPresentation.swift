import SwiftUI

struct VideoDetailPlayerPlaceholderPresentation {
    let loadingProgress: Double
    let loadingMessage: String
    let secondaryLoadingMessage: String?
    let shouldWatchSlowLoading: Bool
    let showsUnavailableVariantBadge: Bool

    init(
        placeholderStore: VideoDetailPlayerPlaceholderRenderStore,
        relatedStore: VideoDetailRelatedRenderStore,
        isTakingLong: Bool
    ) {
        let calculator = VideoDetailPlayerPlaceholderPresentationCalculator(
            playURLState: placeholderStore.playURLState,
            isDetailLoading: placeholderStore.isDetailLoading,
            relatedState: relatedStore.state
        )
        loadingProgress = calculator.loadingProgress
        loadingMessage = calculator.loadingMessage
        secondaryLoadingMessage = calculator.secondaryLoadingMessage(isTakingLong: isTakingLong)
        shouldWatchSlowLoading = calculator.shouldWatchSlowLoading
        showsUnavailableVariantBadge = !placeholderStore.playURLState.isLoading
            && placeholderStore.selectedPlayVariant != nil
    }
}

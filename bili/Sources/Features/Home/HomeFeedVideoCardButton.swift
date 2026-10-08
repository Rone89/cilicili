import SwiftUI

struct HomeFeedVideoCardButton: View {
    let metrics: HomeFeedLayoutMetrics
    let video: VideoItem
    let display: VideoCardDisplayModel
    let actions: HomeFeedContentActions

    var body: some View {
        cardButton.modifier(HomeRecommendationFeedbackMenu(
            video: video,
            actions: actions.recommendationFeedback,
            onTap: { (actions.onVideoSelect ?? actions.onVideoTap)(video) },
            onPress: { actions.onVideoPress(video) }
        ))
    }

    @ViewBuilder
    private var cardButton: some View {
        if let onVideoSelect = actions.onVideoSelect {
            Button {
                onVideoSelect(video)
            } label: {
                HomeFeedVideoCardLabel(
                    metrics: metrics,
                    display: display
                )
            }
            .buttonStyle(.plain)
            .buttonStyle(PressPreloadButtonStyle {
                actions.onVideoPress(video)
            })
        } else {
            Button {
                actions.onVideoTap(video)
            } label: {
                HomeFeedVideoCardLabel(
                    metrics: metrics,
                    display: display
                )
            }
            .buttonStyle(PressPreloadButtonStyle {
                actions.onVideoPress(video)
            })
        }
    }
}

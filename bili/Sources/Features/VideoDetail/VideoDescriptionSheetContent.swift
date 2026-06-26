import SwiftUI
import UIKit

struct VideoDescriptionSheetContent: View {
    @ObservedObject var store: VideoDetailDescriptionRenderStore
    let toggleFollow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VideoTitleText(text: store.titleText.normalizedDetailTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            VideoDescriptionOwnerRow(
                owner: store.owner,
                fanCountText: store.fanCountText,
                isFollowing: store.isFollowing,
                isMutatingInteraction: store.isMutatingInteraction,
                toggleFollow: toggleFollow
            )

            Label(store.publishDateText, systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            BiliLinkedText(
                store.descriptionText,
                font: UIFont.preferredFont(forTextStyle: .body),
                textColor: .primary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

import SwiftUI

struct VideoDetailResolvedInfoContent: View {
    @ObservedObject var store: VideoDetailDescriptionRenderStore
    @Binding var isExpanded: Bool

    private var presentation: VideoDetailInfoPresentation {
        VideoDetailInfoPresentation(store: store, isExpanded: isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VideoDetailInfoTitleText(text: presentation.titleText, isExpanded: isExpanded)

            VideoDetailInfoMetadataRow(
                metadataText: presentation.metadataText,
                hasDescriptionContent: presentation.hasDescriptionContent,
                isExpanded: isExpanded,
                toggleExpansion: toggleExpansion
            )

            if isExpanded {
                VideoDetailExpandedDescriptionText(descriptionText: presentation.descriptionText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    private func toggleExpansion() {
        withAnimation(.snappy(duration: 0.22)) {
            isExpanded.toggle()
        }
    }
}

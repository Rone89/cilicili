import SwiftUI

struct SearchVideoResultRow: View {
    private let display: VideoCardDisplayModel

    init(video: VideoItem) {
        self.display = VideoCardDisplayModel(video: video)
    }

    var body: some View {
        VideoCompactListRow(
            display: display,
            coverSize: CGSize(width: 118, height: 66),
            coverCornerRadius: 10,
            showsCoverBorder: true,
            titleMinHeight: 36,
            authorStyle: .icon("person.crop.circle"),
            metadataStyle: .search
        )
    }
}

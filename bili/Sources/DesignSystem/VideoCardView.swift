import SwiftUI

struct VideoCardView: View, Equatable {
    enum SurfaceStyle: Equatable {
        case elevated
        case blended
    }

    let display: VideoCardDisplayModel
    private let showsPublishTimeInAuthorRow: Bool
    private let showsCoverViewCountBadge: Bool
    private let surfaceStyle: SurfaceStyle
    private let fixedCoverSize: CGSize?
    private let coverMaximumPixelLength: Int
    @State private var coverLoadedState = VideoCoverLoadedState()

    init(
        video: VideoItem,
        showsPublishTimeInAuthorRow: Bool = false,
        showsCoverViewCountBadge: Bool = true,
        surfaceStyle: SurfaceStyle = .elevated,
        fixedCoverSize: CGSize? = nil,
        coverMaximumPixelLength: Int = 1280
    ) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
        self.showsCoverViewCountBadge = showsCoverViewCountBadge
        self.surfaceStyle = surfaceStyle
        self.fixedCoverSize = fixedCoverSize
        self.coverMaximumPixelLength = coverMaximumPixelLength
    }

    init(
        display: VideoCardDisplayModel,
        showsPublishTimeInAuthorRow: Bool = false,
        showsCoverViewCountBadge: Bool = true,
        surfaceStyle: SurfaceStyle = .elevated,
        fixedCoverSize: CGSize? = nil,
        coverMaximumPixelLength: Int = 1280
    ) {
        self.display = display
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
        self.showsCoverViewCountBadge = showsCoverViewCountBadge
        self.surfaceStyle = surfaceStyle
        self.fixedCoverSize = fixedCoverSize
        self.coverMaximumPixelLength = coverMaximumPixelLength
    }

    static func == (lhs: VideoCardView, rhs: VideoCardView) -> Bool {
        lhs.display == rhs.display
            && lhs.showsPublishTimeInAuthorRow == rhs.showsPublishTimeInAuthorRow
            && lhs.showsCoverViewCountBadge == rhs.showsCoverViewCountBadge
            && lhs.surfaceStyle == rhs.surfaceStyle
            && lhs.fixedCoverSize == rhs.fixedCoverSize
            && lhs.coverMaximumPixelLength == rhs.coverMaximumPixelLength
    }

    var body: some View {
        Group {
            switch surfaceStyle {
            case .elevated:
                elevatedBody
            case .blended:
                blendedBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var elevatedBody: some View {
        VideoCardElevatedBody(
            display: display,
            cover: cover,
            showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow
        )
    }

    private var blendedBody: some View {
        VideoCardBlendedBody(
            display: display,
            cover: cover,
            showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow
        )
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottom) {
                    coverImage
                    if coverLoadedState.isLoaded(identity: display.coverLoadIdentity) {
                        coverBottomScrim
                        coverMetaOverlay
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
    }

    @ViewBuilder
    private var coverImage: some View {
        AdaptiveVideoCoverImage(
            display: display,
            style: .exactCrop,
            fixedSize: fixedCoverSize,
            maximumPixelLength: coverMaximumPixelLength,
            onPhaseChange: { phase in
                coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
            }
        )
    }

    private var coverMetaOverlay: some View {
        VideoCoverMetaOverlay(
            viewText: display.viewText,
            durationText: display.durationText,
            showsViewCount: showsCoverViewCountBadge,
            horizontalPadding: 10,
            bottomPadding: 8,
            spacing: 6
        )
    }

    @ViewBuilder
    private var coverBottomScrim: some View {
        if (showsCoverViewCountBadge && !display.viewText.isEmpty) || !display.durationText.isEmpty {
            VideoCoverBottomScrim()
        }
    }
}

import SwiftUI

struct VideoCompactCover: View, Equatable {
    let display: VideoCardDisplayModel
    let size: CGSize
    let maximumPixelLength: Int
    let cornerRadius: CGFloat
    let showsBorder: Bool
    private let badgeInset: CGFloat = 7
    @State private var coverLoadedState = VideoCoverLoadedState()

    static func == (lhs: VideoCompactCover, rhs: VideoCompactCover) -> Bool {
        lhs.display == rhs.display
            && lhs.size == rhs.size
            && lhs.maximumPixelLength == rhs.maximumPixelLength
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.showsBorder == rhs.showsBorder
    }

    var body: some View {
        AdaptiveVideoCoverImage(
            display: display,
            style: .exactCrop,
            fixedSize: size,
            maximumPixelLength: maximumPixelLength,
            onPhaseChange: { phase in
                coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
            }
        )
        .frame(width: size.width, height: size.height)
        .overlay {
            if coverLoadedState.isLoaded(identity: display.coverLoadIdentity), !display.durationText.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    VideoCoverBottomScrim()

                    VideoCoverDurationBadge(
                        display.durationText,
                        maxWidth: max(size.width - badgeInset * 2, 1)
                    )
                    .padding(badgeInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .videoCoverSurface(
            cornerRadius: cornerRadius,
            shadowLevel: .subtle,
            emphasizesBorder: showsBorder
        )
    }
}

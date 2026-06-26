import SwiftUI

struct SearchPosterCover: View {
    let sourceURLString: String?
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let targetPixelSize: Int
    let size: CGSize
    let placeholderSystemImage: String

    var body: some View {
        CachedRemoteImage(
            url: sourceURLString.flatMap { URL(string: $0.biliCoverThumbnailURL(width: thumbnailWidth, height: thumbnailHeight)) },
            fallbackURL: sourceURLString.flatMap(URL.init(string:)),
            targetPixelSize: targetPixelSize,
            animatesAppearance: false
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            SearchImagePlaceholder(systemImage: placeholderSystemImage)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.7)
        }
        .mediaShadow(.subtle)
    }
}

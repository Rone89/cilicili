import SwiftUI
import UIKit

nonisolated struct VideoCardDisplayModel: Identifiable, Equatable {
    let id: String
    let title: String
    let authorName: String
    let viewText: String
    let durationText: String
    let publishTimeText: String
    let metadataSummaryText: String
    let coverURL: URL?
    let largeCoverURL: URL?
    let sourceCoverURL: URL?
    let avatarURLString: String?
    let coverAspectRatio: CGFloat

    init(video: VideoItem) {
        id = video.id
        title = video.title
        authorName = video.owner?.name ?? "Unknown"
        viewText = BiliFormatters.compactCount(video.stat?.view)
        durationText = BiliFormatters.duration(video.duration)
        let formattedPublishTime = BiliFormatters.relativeTime(video.pubdate)
        publishTimeText = formattedPublishTime.isEmpty ? "投稿" : formattedPublishTime
        metadataSummaryText = [
            authorName,
            viewText.isEmpty ? nil : "\(viewText)次观看",
            publishTimeText
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " · ")
        let normalizedCover = video.pic?.normalizedBiliURL()
        sourceCoverURL = normalizedCover.flatMap { URL(string: $0) }
        coverURL = normalizedCover.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 480, height: 270)) }
        largeCoverURL = normalizedCover.flatMap { URL(string: $0.biliImageThumbnailURL(maxSide: 1280)) }
        avatarURLString = video.owner?.face?.normalizedBiliURL()
        coverAspectRatio = CGFloat(video.dimension?.aspectRatio ?? 16.0 / 9.0)
    }

    func coverThumbnailURL(fitting size: CGSize, scale: CGFloat, maximumPixelLength: Int = 1280) -> URL? {
        guard let source = sourceCoverURL?.absoluteString else { return coverURL }
        return URL(string: source.biliCoverThumbnailURL(fitting: size, scale: scale, maximumPixelLength: maximumPixelLength)) ?? coverURL
    }

    func largeThumbnailURL(fitting size: CGSize, scale: CGFloat, maximumPixelLength: Int = 1280) -> URL? {
        guard let source = sourceCoverURL?.absoluteString else { return largeCoverURL ?? coverURL }
        return URL(string: source.biliImageThumbnailURL(fitting: size, scale: scale, maximumPixelLength: maximumPixelLength)) ?? largeCoverURL ?? coverURL
    }

    func coverTargetPixelSize(fitting size: CGSize, scale: CGFloat, maximumPixelLength: Int = 1280) -> Int {
        String.biliThumbnailMaxPixelSide(fitting: size, scale: scale, maximumPixelLength: maximumPixelLength)
    }
}

struct StableVideoTitleText: View {
    enum Style {
        case feedStory
        case feedHeadline
        case compactCard
        case related

        var uiFont: UIFont {
            switch self {
            case .feedStory:
                return UIFontMetrics(forTextStyle: .headline)
                    .scaledFont(for: .systemFont(ofSize: 15.5, weight: .semibold))
            case .feedHeadline:
                return UIFontMetrics(forTextStyle: .headline)
                    .scaledFont(for: .systemFont(ofSize: 15.5, weight: .semibold))
            case .compactCard:
                return UIFontMetrics(forTextStyle: .subheadline)
                    .scaledFont(for: .systemFont(ofSize: 14.5, weight: .semibold))
            case .related:
                return UIFontMetrics(forTextStyle: .subheadline)
                    .scaledFont(for: .systemFont(ofSize: 14.5, weight: .semibold))
            }
        }
    }

    let title: String
    let style: Style
    let lineLimit: Int

    init(_ title: String, style: Style, lineLimit: Int = 2) {
        self.title = title
        self.style = style
        self.lineLimit = lineLimit
    }

    var body: some View {
        StableVideoTitleLabel(title: title, font: style.uiFont, lineLimit: lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(title)
    }
}

struct VideoCoverGlassBadge<Content: View>: View {
    let content: Content
    private let tintOpacity: Double

    init(tintOpacity: Double = 0.16, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.tintOpacity = tintOpacity
    }

    var body: some View {
        content
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .frame(maxWidth: 146, minHeight: 22)
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(.black.opacity(tintOpacity)).interactive(false),
                        in: Capsule()
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .clipped()
    }
}

struct VideoCoverDurationBadge: View {
    let duration: String

    init(_ duration: String) {
        self.duration = duration
    }

    var body: some View {
        Text(duration)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.black.opacity(0.58))
            }
            .frame(maxWidth: 96, alignment: .trailing)
            .shadow(color: .black.opacity(0.42), radius: 1.0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.16), radius: 2.6, x: 0, y: 1.4)
            .clipped()
            .accessibilityLabel("视频时长 \(duration)")
    }
}

struct VideoCoverViewCountBadge: View {
    let viewText: String

    init(_ viewText: String) {
        self.viewText = viewText
    }

    var body: some View {
        Label(viewText, systemImage: "play.fill")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
            .frame(maxWidth: 112, alignment: .leading)
            .shadow(color: .black.opacity(0.42), radius: 1.0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.16), radius: 2.6, x: 0, y: 1.4)
            .clipped()
            .accessibilityLabel("观看次数 \(viewText)")
    }
}

struct VideoCoverPlayBadge: View {
    var size: CGFloat = 40
    var iconSize: CGFloat = 15

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: 1)
            .frame(width: size, height: size)
            .background(.black.opacity(0.52), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .accessibilityHidden(true)
    }
}

struct AdaptiveVideoCoverImage: View {
    enum Style {
        case exactCrop
        case maxSide
    }

    let display: VideoCardDisplayModel
    let style: Style
    var fixedSize: CGSize?
    var maximumPixelLength: Int = 1280

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let fixedSize {
            remoteImage(fitting: fixedSize)
                .frame(width: fixedSize.width, height: fixedSize.height)
                .clipped()
        } else {
            GeometryReader { proxy in
                remoteImage(fitting: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
    }

    @ViewBuilder
    private func remoteImage(fitting size: CGSize) -> some View {
        CachedRemoteImage(
            url: thumbnailURL(fitting: size),
            fallbackURL: display.sourceCoverURL,
            targetPixelSize: display.coverTargetPixelSize(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            ),
            animatesAppearance: false
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } phasePlaceholder: { phase, _ in
            BiliMediaPlaceholder(
                style: .video,
                phase: phase,
                showsSpinner: phase == .loading,
                iconSize: 18
            )
        }
    }

    private func thumbnailURL(fitting size: CGSize) -> URL? {
        switch style {
        case .exactCrop:
            return display.coverThumbnailURL(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            )
        case .maxSide:
            return display.largeThumbnailURL(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            )
        }
    }
}

private struct StableVideoTitleLabel: UIViewRepresentable {
    let title: String
    let font: UIFont
    let lineLimit: Int

    final class Coordinator {
        var lastSignature: Signature?
    }

    struct Signature: Equatable {
        let title: String
        let fontName: String
        let pointSize: CGFloat
        let lineLimit: Int
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = lineLimit
        label.lineBreakMode = titleLineBreakMode
        label.adjustsFontForContentSizeCategory = true
        label.allowsDefaultTighteningForTruncation = true
        label.textAlignment = .natural
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let signature = Signature(
            title: title,
            fontName: font.fontName,
            pointSize: font.pointSize,
            lineLimit: lineLimit
        )
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature

        label.numberOfLines = lineLimit
        label.lineBreakMode = titleLineBreakMode
        label.attributedText = attributedTitle
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width ?? (uiView.bounds.width > 1 ? uiView.bounds.width : nil),
              width > 1
        else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let maxHeight = ceil(font.lineHeight * CGFloat(max(lineLimit, 1)) + 2)
        return CGSize(width: width, height: min(ceil(measured.height), maxHeight))
    }

    private var attributedTitle: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = titleLineBreakMode
        paragraphStyle.alignment = .natural
        paragraphStyle.hyphenationFactor = 0
        if #available(iOS 14.0, *) {
            paragraphStyle.lineBreakStrategy = []
        }
        return NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private var titleLineBreakMode: NSLineBreakMode {
        lineLimit == 1 ? .byTruncatingTail : .byWordWrapping
    }
}

struct VideoFeedStoryCardView: View, Equatable {
    let display: VideoCardDisplayModel
    private let showsHeader: Bool

    init(video: VideoItem, showsHeader: Bool = true) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsHeader = showsHeader
    }

    init(display: VideoCardDisplayModel, showsHeader: Bool = true) {
        self.display = display
        self.showsHeader = showsHeader
    }

    static func == (lhs: VideoFeedStoryCardView, rhs: VideoFeedStoryCardView) -> Bool {
        lhs.display == rhs.display && lhs.showsHeader == rhs.showsHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 8 : 0) {
            if showsHeader {
                header
            }
            mediaContainer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 9) {
            AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 64) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            Text(display.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(display.publishTimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }

    private var mediaContainer: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            title
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
        }
        .mediaShadow(.regular)
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottom) {
                    AdaptiveVideoCoverImage(display: display, style: .exactCrop)

                    coverMetaOverlay
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
    }

    private var coverMetaOverlay: some View {
        HStack(spacing: 8) {
            if !display.viewText.isEmpty {
                VideoCoverGlassBadge {
                    Label(display.viewText, systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer(minLength: 8)

            if !display.durationText.isEmpty {
                VideoCoverDurationBadge(display.durationText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    private var title: some View {
        StableVideoTitleText(display.title, style: .feedStory)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
    }
}

struct YouTubeStyleVideoFeedCardView: View, Equatable {
    let display: VideoCardDisplayModel
    private let showsMetadataSummary: Bool
    private let showsPlayBadge: Bool
    private let fixedCoverAspectRatio: CGFloat?
    private let fixedCoverSize: CGSize?
    private let coverShadowLevel: MediaShadowLevel
    private static let metadataAvatarSide: CGFloat = 34

    init(
        video: VideoItem,
        showsMetadataSummary: Bool = true,
        showsPlayBadge: Bool = false,
        fixedCoverAspectRatio: CGFloat? = nil,
        fixedCoverSize: CGSize? = nil,
        coverShadowLevel: MediaShadowLevel = .control
    ) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsMetadataSummary = showsMetadataSummary
        self.showsPlayBadge = showsPlayBadge
        self.fixedCoverAspectRatio = fixedCoverAspectRatio
        self.fixedCoverSize = fixedCoverSize
        self.coverShadowLevel = coverShadowLevel
    }

    init(
        display: VideoCardDisplayModel,
        showsMetadataSummary: Bool = true,
        showsPlayBadge: Bool = false,
        fixedCoverAspectRatio: CGFloat? = nil,
        fixedCoverSize: CGSize? = nil,
        coverShadowLevel: MediaShadowLevel = .control
    ) {
        self.display = display
        self.showsMetadataSummary = showsMetadataSummary
        self.showsPlayBadge = showsPlayBadge
        self.fixedCoverAspectRatio = fixedCoverAspectRatio
        self.fixedCoverSize = fixedCoverSize
        self.coverShadowLevel = coverShadowLevel
    }

    static func == (lhs: YouTubeStyleVideoFeedCardView, rhs: YouTubeStyleVideoFeedCardView) -> Bool {
        lhs.display == rhs.display
            && lhs.showsMetadataSummary == rhs.showsMetadataSummary
            && lhs.showsPlayBadge == rhs.showsPlayBadge
            && lhs.fixedCoverAspectRatio == rhs.fixedCoverAspectRatio
            && lhs.fixedCoverSize == rhs.fixedCoverSize
            && lhs.coverShadowLevel == rhs.coverShadowLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            metadataRow
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(effectiveCoverAspectRatio, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottomTrailing) {
                    AdaptiveVideoCoverImage(display: display, style: .maxSide, fixedSize: fixedCoverSize)

                    if showsPlayBadge {
                        VideoCoverPlayBadge(size: 40, iconSize: 15)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }

                    if !display.durationText.isEmpty {
                        VideoCoverDurationBadge(display.durationText)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .mediaShadow(coverShadowLevel)
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 9) {
            AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 68) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Self.metadataAvatarSide, height: Self.metadataAvatarSide)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            VStack(alignment: .leading, spacing: 1) {
                StableVideoTitleText(display.title, style: .feedHeadline, lineLimit: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(metadataText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.metadataAvatarSide, alignment: .center)
        }
        .frame(height: Self.metadataAvatarSide)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataText: String {
        showsMetadataSummary ? display.metadataSummaryText : display.authorName
    }

    private var sanitizedCoverAspectRatio: CGFloat {
        min(max(display.coverAspectRatio, 0.56), 2.2)
    }

    private var effectiveCoverAspectRatio: CGFloat {
        fixedCoverAspectRatio ?? sanitizedCoverAspectRatio
    }
}

struct VideoCardView: View, Equatable {
    enum SurfaceStyle: Equatable {
        case elevated
        case blended
    }

    let display: VideoCardDisplayModel
    private let showsPublishTimeInAuthorRow: Bool
    private let surfaceStyle: SurfaceStyle
    private let fixedCoverSize: CGSize?

    init(
        video: VideoItem,
        showsPublishTimeInAuthorRow: Bool = false,
        surfaceStyle: SurfaceStyle = .elevated,
        fixedCoverSize: CGSize? = nil
    ) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
        self.surfaceStyle = surfaceStyle
        self.fixedCoverSize = fixedCoverSize
    }

    init(
        display: VideoCardDisplayModel,
        showsPublishTimeInAuthorRow: Bool = false,
        surfaceStyle: SurfaceStyle = .elevated,
        fixedCoverSize: CGSize? = nil
    ) {
        self.display = display
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
        self.surfaceStyle = surfaceStyle
        self.fixedCoverSize = fixedCoverSize
    }

    static func == (lhs: VideoCardView, rhs: VideoCardView) -> Bool {
        lhs.display == rhs.display
            && lhs.showsPublishTimeInAuthorRow == rhs.showsPublishTimeInAuthorRow
            && lhs.surfaceStyle == rhs.surfaceStyle
            && lhs.fixedCoverSize == rhs.fixedCoverSize
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
        VStack(alignment: .leading, spacing: 0) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                authorRow
            }
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .mediaShadow(.subtle)
    }

    private var blendedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .mediaShadow(.control)

            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                authorRow
            }
            .padding(.horizontal, 2)
        }
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottom) {
                    coverImage
                    coverMetaOverlay
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
    }

    private var titleLabel: some View {
        StableVideoTitleText(display.title, style: .compactCard)
            .frame(minHeight: 36, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var coverImage: some View {
        AdaptiveVideoCoverImage(display: display, style: .exactCrop, fixedSize: fixedCoverSize)
    }

    private var coverMetaOverlay: some View {
        HStack(spacing: 6) {
            if !display.viewText.isEmpty {
                VideoCoverViewCountBadge(display.viewText)
            }

            Spacer(minLength: 6)

            if !display.durationText.isEmpty {
                VideoCoverDurationBadge(display.durationText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    private var authorRow: some View {
        HStack(spacing: 4) {
            AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 48) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 14, height: 14)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            Text(display.authorName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if showsPublishTimeInAuthorRow {
                Spacer(minLength: 6)

                Text(display.publishTimeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

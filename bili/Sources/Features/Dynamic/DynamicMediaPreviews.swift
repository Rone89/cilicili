import SwiftUI

struct DynamicOriginalPreview: View {
    let item: DynamicOriginalItem
    let parentID: String
    let contentWidth: CGFloat?
    private let video: VideoItem?
    private let live: DynamicLive?
    private let liveRoom: LiveRoom?
    private let paidContent: DynamicPaidContent?
    private let paidVideo: VideoItem?
    private let paidContentRendersAsTextOnly: Bool
    private let paidChargeURL: URL?
    private let authorOwner: VideoOwner?
    private let imageItems: [DynamicImageItem]
    private let textSegments: [DynamicTextSegment]
    private let textInput: DynamicAttributedTextInput
    private let topLevelDisplayText: String?

    init(
        item: DynamicOriginalItem,
        parentID: String,
        contentWidth: CGFloat? = nil
    ) {
        self.item = item
        self.parentID = parentID
        self.contentWidth = contentWidth
        self.video = item.archive?.asVideoItem(author: item.author)
        self.live = item.live
        self.liveRoom = item.live?.asLiveRoom(author: item.author)
        self.paidContent = item.paidContent
        self.paidVideo = item.paidContent?.asVideoItem(author: item.author)
        self.paidContentRendersAsTextOnly = item.paidContent?.isChargeArticleLike == true
        self.paidChargeURL = item.paidContent?.chargePageURL(author: item.author)
        self.authorOwner = item.author?.owner
        self.imageItems = item.imageItems.filter { $0.normalizedURL != nil }
        self.textSegments = item.textSegments
        self.textInput = .dynamicFeedHeadline(
            segments: item.textSegments,
            emoteSize: 20,
            maxLines: 5
        )
        self.topLevelDisplayText = DynamicTextSegment.displayText(from: item.textSegments)
    }

    var body: some View {
        originalContent
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.78))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.pink.opacity(0.58))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var originalContent: some View {
        if item.visible == false || !item.hasDisplayableContent {
            DynamicForwardUnavailableView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let author = item.author {
                    if let authorOwner, authorOwner.mid > 0 {
                        NavigationLink {
                            UploaderView(owner: authorOwner)
                        } label: {
                            originalAuthorIdentity(author)
                        }
                        .buttonStyle(.plain)
                    } else {
                        originalAuthorIdentity(author)
                    }
                }

                if topLevelDisplayText?.isEmpty == false {
                    DynamicRichTextView(
                        input: textInput,
                        preferredWidth: originalTextWidth
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let paidContent, paidContentRendersAsTextOnly {
                    DynamicPaidArticleTextRouteLink(content: paidContent, chargeURL: paidChargeURL) {
                        DynamicPaidArticleTextPreview(content: paidContent)
                    }
                } else if let paidContent {
                    DynamicPaidContentRouteLink(content: paidContent, video: paidVideo) {
                        DynamicPaidContentPreview(content: paidContent, style: .compact)
                    }
                } else if let video {
                    VideoRouteLink(video) {
                        DynamicArchivePreview(
                            video: video,
                            style: .compact,
                            showsCoverBadges: false
                        )
                    }
                }

                if let live {
                    DynamicLiveRouteLink(room: liveRoom) {
                        DynamicLivePreview(live: live, style: .compact)
                    }
                }

                if !imageItems.isEmpty {
                    DynamicImageThumbnailStrip(
                        images: imageItems,
                        availableWidth: contentWidth
                    )
                }
            }
        }
    }

    private var originalTextWidth: CGFloat? {
        contentWidth.map { max(floor($0 - 24), 0) }
    }

    private func originalAuthorIdentity(_ author: DynamicAuthor) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.opening")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.pink)

            Text("转发自")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("@\(author.name ?? "Unknown")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

struct DynamicForwardUnavailableView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
            Text("原动态不可见或已删除")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct DynamicPaidContentRouteLink<Label: View>: View {
    let content: DynamicPaidContent
    let video: VideoItem?
    @ViewBuilder let label: () -> Label
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let video {
            VideoRouteLink(video) {
                label()
            }
        } else if let url = content.normalizedJumpURL {
            Button {
                _ = openURL(url)
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            label()
                .opacity(0.78)
        }
    }
}

struct DynamicPaidArticleTextRouteLink<Label: View>: View {
    let content: DynamicPaidContent
    let chargeURL: URL?
    @ViewBuilder let label: () -> Label
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let chargeURL {
            Button {
                _ = openURL(chargeURL)
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            label()
        }
    }
}

struct DynamicPaidArticleTextPreview: View {
    let content: DynamicPaidContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = content.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Text(content.badgeText)
                if content.isLocked {
                    Text("需解锁")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.pink)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.badgeText) \(content.title)")
    }
}

struct DynamicPaidContentPreview: View {
    enum Style {
        case large
        case compact
    }

    let content: DynamicPaidContent
    var style: Style = .large

    var body: some View {
        switch style {
        case .large:
            largeContent
        case .compact:
            compactContent
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 7) {
                title
                metadata
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.badgeText) \(content.title)")
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            cover
                .frame(width: 118, height: 118 * 9 / 16)

            VStack(alignment: .leading, spacing: 7) {
                title
                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.badgeText) \(content.title)")
    }

    private var cover: some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack {
                BiliMediaPlaceholder(style: .video, iconSize: 17)

                if let coverURLString = content.normalizedCoverURL {
                    CachedRemoteImage(
                        url: URL(string: coverURLString.biliCoverThumbnailURL(width: 640, height: 360)),
                        fallbackURL: URL(string: coverURLString),
                        targetPixelSize: 640,
                        animatesAppearance: false
                    ) { image in
                        image.resizable().scaledToFill()
                    } phasePlaceholder: { phase, _ in
                        BiliMediaPlaceholder(
                            style: .video,
                            phase: phase,
                            iconSize: 17
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }

                VideoCoverBottomScrim()

                if content.kind == .video {
                    DynamicVideoPlayBadge(size: style == .large ? 34 : 28, iconSize: style == .large ? 14 : 12)
                        .padding(style == .large ? 8 : 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                DynamicPaidContentBadge(content: content)
                    .padding(style == .large ? 10 : 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: style == .large ? 16 : 10, style: .continuous))
        .mediaShadow(style == .large ? .control : .regular)
    }

    private var title: some View {
        Text(content.title)
            .font(style == .large ? .system(size: 16, weight: .semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            Label(kindText, systemImage: kindIcon)
                .foregroundStyle(content.isChargeExclusive ? .pink : .secondary)

            if let subtitle = content.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .lineLimit(1)
            }

            if content.isLocked {
                Label("需解锁", systemImage: "lock.fill")
                    .foregroundStyle(.pink)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var kindText: String {
        switch content.kind {
        case .video:
            return "视频"
        case .article:
            return "专栏"
        case .course:
            return "课程"
        case .collection:
            return "合集"
        case .unknown:
            return "内容"
        }
    }

    private var kindIcon: String {
        switch content.kind {
        case .video:
            return "play.rectangle.fill"
        case .article:
            return "doc.text.fill"
        case .course:
            return "graduationcap.fill"
        case .collection:
            return "rectangle.stack.fill"
        case .unknown:
            return "sparkles"
        }
    }
}

private struct DynamicPaidContentBadge: View {
    let content: DynamicPaidContent

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Label(content.badgeText, systemImage: content.isChargeExclusive ? "bolt.fill" : "sparkles")
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .biliPlayerClearGlass(interactive: false, in: Capsule())
        }
    }
}

struct DynamicArchivePreview: View {
    enum Style {
        case large
        case compact
    }

    private static let compactCoverSize = CGSize(width: 118, height: 66)

    let video: VideoItem
    let display: VideoCardDisplayModel
    var style: Style = .large
    var showsHeader = true
    var showsCoverBadges = true

    init(
        video: VideoItem,
        style: Style = .large,
        showsHeader: Bool = true,
        showsCoverBadges: Bool = true
    ) {
        self.video = video
        self.display = VideoCardDisplayModel(video: video)
        self.style = style
        self.showsHeader = showsHeader
        self.showsCoverBadges = showsCoverBadges
    }

    var body: some View {
        switch style {
        case .large:
            largeContent
        case .compact:
            compactContent
        }
    }

    private var largeContent: some View {
        YouTubeStyleVideoFeedCardView(
            display: display,
            showsMetadataSummary: false,
            showsPlayBadge: true,
            fixedCoverAspectRatio: 16 / 9,
            coverShadowLevel: .control
        )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("瑙嗛 \(video.title)")
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            cover(
                showsPlayGlyph: showsCoverBadges,
                showsDurationBadge: showsCoverBadges,
                aspectRatio: 16 / 9,
                fixedSize: Self.compactCoverSize
            )
                .frame(width: Self.compactCoverSize.width, height: Self.compactCoverSize.height)

            VStack(alignment: .leading, spacing: 7) {
                DynamicVideoTitleText(
                    video.title,
                    style: .compact,
                    lineLimit: 2
                )

                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cover(
        showsPlayGlyph: Bool,
        showsDurationBadge: Bool = true,
        aspectRatio: CGFloat,
        fixedSize: CGSize? = nil
    ) -> some View {
        FixedAspectPreview(aspectRatio: aspectRatio) {
            ZStack {
                Color.clear

                AdaptiveVideoCoverImage(display: display, style: .exactCrop, fixedSize: fixedSize)

                if showsPlayGlyph || showsDurationBadge {
                    VideoCoverBottomScrim()
                }

                if showsPlayGlyph {
                    DynamicVideoPlayBadge(size: 28, iconSize: 12)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if showsDurationBadge, video.duration != nil {
                    VideoCoverDurationBadge(BiliFormatters.duration(video.duration))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .background(BiliMediaPlaceholder(style: .video, iconSize: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .mediaShadow(.control)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            if let ownerName = video.owner?.name, !ownerName.isEmpty {
                Text(ownerName)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct FixedAspectPreview<Content: View>: View {
    let aspectRatio: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipped()
    }
}

struct DynamicVideoPlayBadge: View {
    var size: CGFloat = 48
    var iconSize: CGFloat = 18

    var body: some View {
        VideoCoverPlayBadge(size: size, iconSize: iconSize)
    }
}

struct DynamicLivePreview: View {
    enum Style {
        case large
        case compact
    }

    let live: DynamicLive
    var style: Style = .large

    var body: some View {
        switch style {
        case .large:
            largeContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("鐩存挱 \(live.displayTitle)")
        case .compact:
            compactContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("鐩存挱 \(live.displayTitle)")
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover(showsCenterBadge: false)

            Text(live.displayTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)

            metadata
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            cover(showsCenterBadge: false)
                .frame(width: 118, height: 118 * 9 / 16)

            VStack(alignment: .leading, spacing: 7) {
                Text(live.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cover(showsCenterBadge: Bool) -> some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack(alignment: .topLeading) {
                Color.clear

                let sourceURLString = live.normalizedCoverURL
                CachedRemoteImage(
                    url: sourceURLString.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 420, height: 236)) },
                    fallbackURL: sourceURLString.flatMap(URL.init(string:)),
                    targetPixelSize: 420,
                    animatesAppearance: false
                ) { image in
                    image.resizable().scaledToFill()
                } phasePlaceholder: { phase, _ in
                    BiliMediaPlaceholder(
                        style: .video,
                        phase: phase,
                        iconSize: 17
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if showsCenterBadge {
                    Label("直播中", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Text(live.statusText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: Capsule())
                    .padding(8)
            }
        }
        .background(BiliMediaPlaceholder(style: .video, iconSize: 17))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .mediaShadow(.regular)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            Label(live.statusText, systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.pink)

            if let viewerText = live.viewerText {
                Text(viewerText)
            }

            if let areaName = live.areaName, !areaName.isEmpty {
                Text(areaName)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct DynamicLiveRouteLink<Label: View>: View {
    let room: LiveRoom?
    @ViewBuilder let label: () -> Label
    @State private var selectedRoom: LiveRoom?

    var body: some View {
        Button {
            selectedRoom = room
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(room == nil)
        .opacity(room == nil ? 0.72 : 1)
        .navigationDestination(item: $selectedRoom) { room in
            LiveRoomDetailView(seedRoom: room)
        }
    }
}

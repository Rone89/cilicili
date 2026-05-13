import SwiftUI

struct VideoCardDisplayModel: Identifiable, Equatable {
    let id: String
    let title: String
    let authorName: String
    let viewText: String
    let durationText: String
    let publishTimeText: String
    let coverURL: URL?
    let avatarURL: URL?

    init(video: VideoItem) {
        id = video.id
        title = video.title
        authorName = video.owner?.name ?? "Unknown"
        viewText = BiliFormatters.compactCount(video.stat?.view)
        durationText = BiliFormatters.duration(video.duration)
        let formattedPublishTime = BiliFormatters.relativeTime(video.pubdate)
        publishTimeText = formattedPublishTime.isEmpty ? "投稿" : formattedPublishTime
        coverURL = video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 480, height: 270)) }
        avatarURL = video.owner?.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 48)) }
    }
}

struct VideoFeedStoryCardView: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 12 : 0) {
            if showsHeader {
                header
                coverContainer
            } else {
                mediaContainer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(size: 50, targetPixelSize: 72, placeholderSize: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(display.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Text(display.authorName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(display.publishTimeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 2)
    }

    private func avatar(size: CGFloat, targetPixelSize: Int, placeholderSize: CGFloat) -> some View {
        CachedRemoteImage(
            url: display.avatarURL,
            targetPixelSize: targetPixelSize
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: placeholderSize, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var coverContainer: some View {
        cover
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, y: 3)
    }

    private var mediaContainer: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            title
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 3)
    }

    private var cover: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)

            ZStack(alignment: .bottom) {
                Color.gray.opacity(0.12)

                CachedRemoteImage(
                    url: display.coverURL,
                    targetPixelSize: 760
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.12)
                        .overlay(ProgressView())
                }
                .frame(width: width, height: height)
                .clipped()

                coverMetaOverlay
                    .frame(width: width, height: height, alignment: .bottom)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var coverMetaOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.64)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 48)

            HStack(spacing: 10) {
                Label(display.viewText, systemImage: "play.fill")
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(display.durationText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.bottom, 7)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
        }
    }

    private var title: some View {
        Text(display.title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
    }
}
struct VideoCardView: View {
    let display: VideoCardDisplayModel
    private let showsPublishTimeInAuthorRow: Bool

    init(video: VideoItem, showsPublishTimeInAuthorRow: Bool = false) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
    }

    init(display: VideoCardDisplayModel, showsPublishTimeInAuthorRow: Bool = false) {
        self.display = display
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                Text(display.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(height: 38, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                authorRow
            }
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private var cover: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)

            ZStack(alignment: .bottom) {
                Color.gray.opacity(0.12)
                coverImage
                    .frame(width: width, height: height)
                    .clipped()

                coverMetaOverlay
                    .frame(width: width, height: height, alignment: .bottom)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var coverImage: some View {
        CachedRemoteImage(
            url: display.coverURL,
            targetPixelSize: 540
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.12)
                .overlay(ProgressView())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var coverMetaOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 42)

            HStack(spacing: 8) {
                Label(display.viewText, systemImage: "play.fill")
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(display.durationText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.bottom, 5)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
        }
    }

    private var authorRow: some View {
        HStack(spacing: 4) {
            CachedRemoteImage(
                url: display.avatarURL,
                targetPixelSize: 48
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 15, height: 15)
            .clipShape(Circle())

            Text(display.authorName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if showsPublishTimeInAuthorRow {
                Spacer(minLength: 6)

                Text(display.publishTimeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

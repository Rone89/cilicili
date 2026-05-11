import SwiftUI

struct VideoCardDisplayModel: Identifiable, Equatable {
    let id: String
    let title: String
    let authorName: String
    let viewText: String
    let durationText: String
    let coverURL: URL?
    let avatarURL: URL?

    init(video: VideoItem) {
        id = video.id
        title = video.title
        authorName = video.owner?.name ?? "未知作者"
        viewText = BiliFormatters.compactCount(video.stat?.view)
        durationText = BiliFormatters.duration(video.duration)
        coverURL = video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 480, height: 270)) }
        avatarURL = video.owner?.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 48)) }
    }
}

struct VideoCardView: View {
    let display: VideoCardDisplayModel

    init(video: VideoItem) {
        self.display = VideoCardDisplayModel(video: video)
    }

    init(display: VideoCardDisplayModel) {
        self.display = display
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
        Rectangle()
            .fill(Color.gray.opacity(0.12))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                coverImage
            }
            .overlay(alignment: .bottom) {
                coverMetaOverlay
            }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

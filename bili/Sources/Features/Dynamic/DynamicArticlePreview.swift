import SwiftUI

private struct DynamicArticleFeedContextKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dynamicArticleFeedContext: Bool {
        get { self[DynamicArticleFeedContextKey.self] }
        set { self[DynamicArticleFeedContextKey.self] = newValue }
    }
}

struct DynamicArticlePreview: View {
    let article: DynamicArticle

    var body: some View {
        Group {
            if let url = article.url {
                AppLinkButton(url: url) { content }
                    .accessibilityHint("打开专栏全文")
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover = article.cover {
                FixedAspectPreview(aspectRatio: 16 / 9) {
                    CachedRemoteImage(url: URL(string: cover), targetPixelSize: 640, animatesAppearance: false) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        BiliMediaPlaceholder(style: .video, iconSize: 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .videoCoverSurface(cornerRadius: 16, shadowLevel: .control)
            }
            Text(article.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
            if let summary = article.summary, summary != article.title {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            Label("查看专栏", systemImage: "doc.text")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

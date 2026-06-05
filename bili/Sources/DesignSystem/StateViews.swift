import SwiftUI

struct ErrorStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        BiliContentStateSurface(
            title: title,
            message: message,
            systemImage: "exclamationmark.triangle",
            tint: .orange
        ) {
            if let retry {
                Button(action: retry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.pink)
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        BiliContentStateSurface(
            title: title,
            message: message,
            systemImage: systemImage,
            tint: .secondary
        )
    }
}

struct InlineLoadingStateView: View {
    var title: String
    var systemImage: String = "arrow.triangle.2.circlepath"

    var body: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)

            Label(title, systemImage: systemImage)
                .labelStyle(.titleOnly)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityLabel(title)
    }
}

private struct BiliContentStateSurface<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let actions: Actions

    init(
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(Color(.tertiarySystemFill), in: Circle())

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
        }
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }
}

struct SkeletonSurface: View {
    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill).opacity(0.64))
            .accessibilityHidden(true)
    }
}

struct BiliMediaPlaceholder: View {
    enum Style: Equatable {
        case video
        case image

        var systemImage: String {
            switch self {
            case .video:
                return "play.rectangle.fill"
            case .image:
                return "photo.fill"
            }
        }
    }

    var style: Style = .video
    var phase: RemoteImageLoadingPhase = .loading
    var showsSpinner = false
    var iconSize: CGFloat = 20

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.tertiarySystemFill).opacity(0.78),
                    Color(.secondarySystemFill).opacity(0.48),
                    Color(.tertiarySystemFill).opacity(0.66)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                let stripeWidth = max(proxy.size.width * 0.36, 80)

                Rectangle()
                    .fill(.white.opacity(0.045))
                    .frame(width: stripeWidth)
                    .rotationEffect(.degrees(14))
                    .offset(x: proxy.size.width * 0.18, y: -proxy.size.height * 0.18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }

            ZStack {
                Circle()
                    .fill(Color(.systemBackground).opacity(0.46))
                    .frame(width: iconSize * 2.05, height: iconSize * 2.05)

                Image(systemName: phase == .failed ? "exclamationmark.triangle.fill" : style.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(phase == .failed ? Color.orange : Color.secondary.opacity(0.72))
            }

            if phase == .failed {
                Text("加载失败")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color(.systemBackground).opacity(0.42), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 9)
            }

            if showsSpinner, phase != .failed {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if phase == .failed {
            return style == .video ? "视频封面加载失败" : "图片加载失败"
        }
        return style == .video ? "正在加载视频封面" : "正在加载图片"
    }
}

struct SkeletonBlock: View {
    enum Shape {
        case rounded(CGFloat)
        case capsule
        case circle
    }

    var width: CGFloat?
    var height: CGFloat
    var shape: Shape = .rounded(8)

    var body: some View {
        block
            .frame(width: width, height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var block: some View {
        switch shape {
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.64))
        case .capsule:
            Capsule()
                .fill(Color(.tertiarySystemFill).opacity(0.64))
        case .circle:
            Circle()
                .fill(Color(.tertiarySystemFill).opacity(0.64))
        }
    }
}

struct SkeletonAspectBlock: View {
    var aspectRatio: CGFloat = 16 / 9
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.tertiarySystemFill).opacity(0.64))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

struct VideoFeedSkeletonCard: View {
    enum Style {
        case singleColumn
        case grid
    }

    let style: Style

    var body: some View {
        switch style {
        case .singleColumn:
            singleColumnBody
        case .grid:
            gridBody
        }
    }

    private var singleColumnBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonAspectBlock(cornerRadius: 16)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 18, shape: .rounded(5))
                SkeletonBlock(width: 206, height: 17, shape: .rounded(5))

                HStack(spacing: 6) {
                    SkeletonBlock(width: 26, height: 26, shape: .circle)
                    SkeletonBlock(width: 168, height: 12, shape: .capsule)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 14)
        .accessibilityLabel("正在加载视频")
    }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonAspectBlock(cornerRadius: 15)

            SkeletonBlock(height: 15, shape: .rounded(5))
            SkeletonBlock(width: 104, height: 14, shape: .rounded(5))

            HStack(spacing: 5) {
                SkeletonBlock(width: 15, height: 15, shape: .circle)
                SkeletonBlock(width: 92, height: 11, shape: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel("正在加载视频")
    }
}

struct DynamicFeedSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SkeletonBlock(width: 38, height: 38, shape: .circle)

                SkeletonBlock(width: 132, height: 14, shape: .capsule)

                Spacer(minLength: 10)

                SkeletonBlock(width: 52, height: 11, shape: .capsule)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 17, shape: .rounded(5))
                SkeletonBlock(width: 260, height: 17, shape: .rounded(5))
            }
            .padding(.horizontal, 12)

            SkeletonAspectBlock(cornerRadius: 18)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                SkeletonBlock(width: 74, height: 32, shape: .capsule)
                SkeletonBlock(width: 74, height: 32, shape: .capsule)
                SkeletonBlock(width: 74, height: 32, shape: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .padding(.vertical, 18)
        .accessibilityLabel("正在加载动态")
    }
}

struct CommentLoadingSkeletonList: View {
    var count: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                CommentLoadingSkeletonRow()
                    .padding(.vertical, 12)

                if index != count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .accessibilityLabel("正在加载评论")
    }
}

struct CommentLoadingSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SkeletonBlock(width: 40, height: 40, shape: .circle)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(width: 104, height: 13, shape: .capsule)
                SkeletonBlock(height: 14, shape: .rounded(5))
                SkeletonBlock(width: 230, height: 14, shape: .rounded(5))

                HStack(spacing: 12) {
                    SkeletonBlock(width: 52, height: 10, shape: .capsule)
                    SkeletonBlock(width: 38, height: 10, shape: .capsule)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchResultSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: 112, height: 70, shape: .rounded(8))

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 14, shape: .rounded(5))
                SkeletonBlock(width: 190, height: 14, shape: .rounded(5))
                SkeletonBlock(width: 118, height: 11, shape: .capsule)
                SkeletonBlock(width: 86, height: 10, shape: .capsule)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("正在加载搜索结果")
    }
}

struct LiveRoomSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonAspectBlock(cornerRadius: 12)

            SkeletonBlock(height: 14, shape: .rounded(5))
            SkeletonBlock(width: 112, height: 14, shape: .rounded(5))

            HStack(spacing: 6) {
                SkeletonBlock(width: 20, height: 20, shape: .circle)
                SkeletonBlock(width: 84, height: 11, shape: .capsule)
            }

            SkeletonBlock(width: 96, height: 10, shape: .capsule)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel("正在加载直播间")
    }
}

import SwiftUI

private struct DynamicPGCCardEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dynamicPGCCardEnabled: Bool {
        get { self[DynamicPGCCardEnabledKey.self] }
        set { self[DynamicPGCCardEnabledKey.self] = newValue }
    }
}

struct DynamicPGCRouteLink: View {
    let pgc: DynamicPGC
    var compact = false
    @Environment(\.openPgcSeasonRouteAction) private var openSeason
    @State private var selectedRoute: PgcSeasonRoute?

    var body: some View {
        Group {
            if let route = pgc.playbackRoute {
                Button {
                    if let openSeason {
                        openSeason(route)
                    } else {
                        selectedRoute = route
                    }
                } label: {
                    DynamicPGCPreview(pgc: pgc, compact: compact)
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开对应番剧分集")
            } else if let url = pgc.jumpURL {
                AppLinkButton(url: url) {
                    DynamicPGCPreview(pgc: pgc, compact: compact)
                }
                .accessibilityHint("打开番剧链接")
            } else {
                DynamicPGCPreview(pgc: pgc, compact: compact)
            }
        }
        .accessibilityIdentifier("dynamic.pgc.card.\(pgc.episodeID ?? pgc.seasonID ?? 0)")
        .navigationDestination(item: $selectedRoute) { route in
            PgcSeasonPlaybackRouteView(route: route)
        }
    }
}

private struct DynamicPGCPreview: View {
    let pgc: DynamicPGC
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                HStack(alignment: .top, spacing: 10) {
                    cover.frame(width: 118, height: 66)
                    details
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    cover
                    details
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("番剧 \(pgc.title)")
    }

    private var cover: some View {
        let pixelWidth = compact ? 420 : 960
        return FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack {
                CachedRemoteImage(
                    url: pgc.cover.flatMap { URL(string: $0.biliCoverThumbnailURL(width: pixelWidth, height: pixelWidth * 9 / 16)) },
                    fallbackURL: pgc.cover.flatMap(URL.init(string:)),
                    targetPixelSize: pixelWidth,
                    animatesAppearance: false
                ) { image in
                    image.resizable().scaledToFill()
                } phasePlaceholder: { phase, _ in
                    BiliMediaPlaceholder(style: .video, phase: phase, iconSize: 17)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                VideoCoverBottomScrim()
                if pgc.playbackRoute != nil || pgc.jumpURL != nil {
                    DynamicVideoPlayBadge(size: 28, iconSize: 12)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                if let duration = pgc.durationText {
                    VideoCoverDurationBadge(duration)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                if let badge = pgc.badgeText {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .videoCoverBadgeBackground(style: .regular, in: Capsule())
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .videoCoverSurface(cornerRadius: compact ? 8 : 16, shadowLevel: .control)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            DynamicVideoTitleText(pgc.title, style: compact ? .compact : .feed)
            HStack(spacing: 12) {
                if let play = pgc.playText {
                    Label(play, systemImage: "play")
                }
                if let danmaku = pgc.danmakuText {
                    Label(danmaku, systemImage: "text.bubble")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if pgc.playbackRoute == nil && pgc.jumpURL == nil {
                Text("暂无可用的播放入口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

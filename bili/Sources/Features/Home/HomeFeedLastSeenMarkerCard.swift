import SwiftUI

struct HomeFeedLastSeenMarkerCard: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let metrics: HomeFeedLayoutMetrics
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            switch metrics.mode {
            case .singleColumn:
                singleColumnLabel
            case .doubleColumn:
                doubleColumnLabel
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("上次看到这里，点击刷新")
    }

    private var singleColumnLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover(cornerRadius: 18)

            HStack(alignment: .center, spacing: 9) {
                markerAvatar(size: 34, iconSize: 15)

                VStack(alignment: .leading, spacing: 1) {
                    StableVideoTitleText("上次看到这里", style: .feedHeadline, lineLimit: 1)

                    Text("点击刷新推荐")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(height: 34, alignment: .center)
            }
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var doubleColumnLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover(cornerRadius: 15)

            VStack(alignment: .leading, spacing: 4) {
                StableVideoTitleText("上次看到这里", style: .compactCard)
                    .frame(minHeight: 36, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    markerAvatar(size: 14, iconSize: 8)

                    Text("点击刷新")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("推荐")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func cover(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack {
                    shape
                        .fill(Color(.secondarySystemGroupedBackground).opacity(0.92))

                    shape
                        .fill(Color(.tertiarySystemFill).opacity(0.55))

                    VStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(appTintColor)

                        Text("点击刷新")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTintColor)
                            .lineLimit(1)
                    }
                }
                .biliPlayerClearGlass(interactive: true, in: shape)
            }
            .frame(maxWidth: .infinity)
    }

    private func markerAvatar(size: CGFloat, iconSize: CGFloat) -> some View {
        Circle()
            .fill(Color(.tertiarySystemFill).opacity(0.70))
            .overlay {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .biliPlayerClearGlass(interactive: false, in: Circle())
            .mediaShadow(.subtle)
    }
}

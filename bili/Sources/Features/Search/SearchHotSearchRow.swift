import SwiftUI

struct SearchHotSearchRow: View {
    let item: HotSearchItem
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            SearchRankBadge(index: index)

            Text(item.showName ?? item.keyword)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SearchHotSearchSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 22, height: 22)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 142, height: 15)

            Spacer(minLength: 8)

            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct SearchRankBadge: View {
    let index: Int

    private var rankColor: Color {
        switch index {
        case 0:
            return .pink
        case 1:
            return .orange
        case 2:
            return .yellow
        default:
            return .secondary
        }
    }

    var body: some View {
        Text("\(index + 1)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(index < 3 ? .white : rankColor)
            .frame(width: 22, height: 22)
            .background {
                if index < 3 {
                    Circle()
                        .fill(rankColor.gradient)
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                }
            }
            .accessibilityHidden(true)
    }
}

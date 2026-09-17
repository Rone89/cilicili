import SwiftUI

struct VideoDetailActionStripFollowControl: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let isFollowing: Bool
    let canFollow: Bool
    let isMutating: Bool
    let action: () -> Void
    let usesPlainStyle: Bool
    let height: CGFloat

    init(
        isFollowing: Bool,
        canFollow: Bool,
        isMutating: Bool,
        action: @escaping () -> Void,
        usesPlainStyle: Bool = false,
        height: CGFloat = VideoDetailActionStrip.Metrics.followHeight
    ) {
        self.isFollowing = isFollowing
        self.canFollow = canFollow
        self.isMutating = isMutating
        self.action = action
        self.usesPlainStyle = usesPlainStyle
        self.height = height
    }

    var body: some View {
        let foregroundStyle = isFollowing ? appTintColor : Color.secondary

        Button(action: action) {
            VideoDetailActionStripFollowLabel(
                isFollowing: isFollowing,
                foregroundStyle: foregroundStyle,
                height: height,
                usesPlainStyle: usesPlainStyle
            )
        }
        .disabled(!canFollow || isMutating)
        .opacity((canFollow && !isMutating) ? 1 : 0.58)
        .accessibilityLabel(isFollowing ? "已关注" : "关注")
        .videoDetailActionStripButtonAppearance(
            shape: .capsule,
            usesPlainStyle: usesPlainStyle,
            tint: usesPlainStyle ? foregroundStyle : nil
        )
    }
}

private struct VideoDetailActionStripFollowLabel: View {
    let isFollowing: Bool
    let foregroundStyle: Color
    let height: CGFloat
    let usesPlainStyle: Bool

    var body: some View {
        Text(isFollowing ? "已关注" : "关注")
            .font(
                usesPlainStyle
                    ? .subheadline.weight(.semibold)
                    : .caption2.weight(.semibold)
            )
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

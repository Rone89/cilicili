import SwiftUI

struct LiveRoomCoverOverlay: View {
    let onlineText: String?

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack {
                LiveRoomStatusBadge()
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if let onlineText {
                    LiveRoomOnlineBadge(text: onlineText)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct LiveRoomStatusBadge: View {
    var body: some View {
        Label("直播中", systemImage: "dot.radiowaves.left.and.right")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .biliPlayerClearGlass(interactive: false, in: Capsule())
            .liveRoomCoverControlShadow()
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 76, alignment: .leading)
            .clipped()
    }
}

struct LiveRoomOnlineBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "person.2.fill")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .biliPlayerClearGlass(interactive: false, in: Capsule())
            .liveRoomCoverControlShadow()
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 86, alignment: .leading)
            .clipped()
    }
}

private extension View {
    func liveRoomCoverControlShadow() -> some View {
        shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
    }
}

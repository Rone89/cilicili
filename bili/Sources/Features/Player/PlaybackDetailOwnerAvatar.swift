import SwiftUI

/// Shared owner avatar used by video and live playback detail pages.
struct PlaybackDetailOwnerAvatar: View {
    let owner: VideoOwner?
    let fallbackURLString: String?
    let side: CGFloat
    let pixelSize: Int
    let showsShadow: Bool
    let showsBorder: Bool

    init(
        owner: VideoOwner?,
        fallbackURLString: String? = nil,
        side: CGFloat,
        pixelSize: Int = 112,
        showsShadow: Bool = true,
        showsBorder: Bool = true
    ) {
        self.owner = owner
        self.fallbackURLString = fallbackURLString
        self.side = side
        self.pixelSize = pixelSize
        self.showsShadow = showsShadow
        self.showsBorder = showsBorder
    }

    var body: some View {
        if let owner, owner.mid > 0 {
            VideoOwnerRouteLink(owner: owner) {
                avatarImage(urlString: owner.face?.normalizedBiliURL())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("打开 \(owner.name) 的主页")
        } else {
            avatarImage(urlString: fallbackURLString?.normalizedBiliURL())
                .opacity(fallbackURLString == nil ? 0.58 : 1)
                .accessibilityLabel("UP主头像")
        }
    }

    private func avatarImage(urlString: String?) -> some View {
        PlaybackDetailOwnerAvatarImage(
            urlString: urlString,
            side: side,
            pixelSize: pixelSize,
            showsShadow: showsShadow,
            showsBorder: showsBorder
        )
    }
}

struct PlaybackDetailOwnerAvatarImage: View {
    @Environment(\.colorScheme) private var colorScheme

    let urlString: String?
    let side: CGFloat
    let pixelSize: Int
    let showsShadow: Bool
    let showsBorder: Bool

    var body: some View {
        Group {
            if showsShadow {
                avatarSurface
                    .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2.2)
                    .shadow(color: .black.opacity(0.10), radius: 1.2, x: 0, y: 0.6)
            } else {
                avatarSurface
            }
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
    }

    private var avatarSurface: some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: pixelSize) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay {
            if showsBorder {
                Circle()
                    .strokeBorder(outerStrokeColor, lineWidth: 1)
            }
        }
        .overlay {
            if showsBorder {
                Circle()
                    .inset(by: 1)
                    .strokeBorder(innerStrokeColor, lineWidth: 0.6)
            }
        }
    }

    private var outerStrokeColor: Color {
        switch colorScheme {
        case .dark:
            return .white.opacity(0.22)
        default:
            return .black.opacity(0.12)
        }
    }

    private var innerStrokeColor: Color {
        switch colorScheme {
        case .dark:
            return .white.opacity(0.12)
        default:
            return .white.opacity(0.46)
        }
    }
}

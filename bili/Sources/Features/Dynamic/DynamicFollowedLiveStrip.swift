import SwiftUI

struct FollowedLiveStrip: View {
    let rooms: [LiveRoom]

    var body: some View {
        if !rooms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("正在直播")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 2)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(rooms) { room in
                            NavigationLink(value: room) {
                                FollowedLiveAvatar(room: room)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .padding(.top, 4)
            .padding(.bottom, 10)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

private struct FollowedLiveAvatar: View {
    let room: LiveRoom

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                AvatarRemoteImage(urlString: room.face, pixelSize: 96) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.pink.opacity(0.72), lineWidth: 1.5)
                }
                .mediaShadow(.regular)

                Text("直播中")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .glassEffect(.regular, in: Capsule())
                    .offset(y: 4)
            }

            Text(anchorName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 58)
        }
        .frame(width: 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(anchorName) 正在直播")
    }

    private var anchorName: String {
        let trimmedName = room.uname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "UP 主" : trimmedName
    }
}

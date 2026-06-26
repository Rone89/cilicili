import SwiftUI

struct MineLoggedInHeaderView: View {
    let avatarURLString: String?
    let username: String
    let uidText: String

    var body: some View {
        HStack(spacing: 12) {
            AvatarRemoteImage(urlString: avatarURLString, pixelSize: 128) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.headline)
                Text(uidText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MineLoginPanelView: View {
    let message: String
    let onQRCodeLogin: () -> Void
    let onWebLogin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.pink)

            Text(message.isEmpty ? "使用 B 站扫码或网页登录，登录后会自动保存 Cookie。" : message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button(action: onQRCodeLogin) {
                    Label("扫码登录", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)

                Button(action: onWebLogin) {
                    Label("网页登录", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

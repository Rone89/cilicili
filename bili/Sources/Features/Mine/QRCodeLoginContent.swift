import SwiftUI

struct QRCodeLoginContent: View {
    let state: QRCodeLoginState
    let refresh: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            QRCodeLoginLoadingState(message: state.message)

        case .waiting(let info, _), .scanned(let info, _):
            QRCodeLoginActiveState(
                state: state,
                info: info,
                refresh: refresh
            )

        case .expired(let message):
            QRCodeLoginRetryState(
                systemImage: "qrcode",
                title: "二维码已过期",
                message: message,
                refresh: refresh
            )

        case .failed(let message):
            QRCodeLoginRetryState(
                systemImage: "exclamationmark.triangle",
                title: "二维码登录失败",
                message: message,
                refresh: refresh
            )

        case .succeeded(let message):
            QRCodeLoginSucceededState(message: message)
        }
    }
}

private struct QRCodeLoginLoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct QRCodeLoginActiveState: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let state: QRCodeLoginState
    let info: QRCodeLoginInfo
    let refresh: () -> Void

    private var statusIcon: String {
        if case .scanned = state {
            return "checkmark.circle"
        }
        return "qrcode.viewfinder"
    }

    private var statusColor: Color {
        if case .scanned = state {
            return appTintColor
        }
        return .secondary
    }

    var body: some View {
        VStack(spacing: 18) {
            QRCodeImage(value: info.url)
                .frame(width: 236, height: 236)
                .padding(14)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Label(state.message, systemImage: statusIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)

            Button(action: refresh) {
                Label("刷新二维码", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct QRCodeLoginRetryState: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let systemImage: String
    let title: String
    let message: String
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: refresh) {
                Label("重新生成", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(appTintColor)
        }
    }
}

private struct QRCodeLoginSucceededState: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.green)
            Text(message)
                .font(.headline)
        }
    }
}

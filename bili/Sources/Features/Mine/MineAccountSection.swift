import SwiftUI

struct MineAccountSection: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var sessionStore: SessionStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void

    var body: some View {
        Section {
            if sessionStore.isLoggedIn {
                MineLoggedInHeaderView(
                    avatarURLString: sessionStore.user?.face,
                    username: sessionStore.user?.uname ?? "Logged in",
                    uidText: "UID \(sessionStore.user?.mid ?? 0)"
                )

                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                MineLoginPanelView(
                    message: viewModel.loginMessage,
                    onQRCodeLogin: onQRCodeLogin,
                    onSMSLogin: onSMSLogin,
                    onWebLogin: onWebLogin
                )
            }
        }
    }
}

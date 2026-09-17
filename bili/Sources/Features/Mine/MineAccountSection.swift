import SwiftUI

struct MineAccountSection: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var sessionStore: SessionStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        Section {
            if sessionStore.isLoggedIn {
                MineAccountSwitcherMenu(
                    sessionStore: sessionStore,
                    onOpenRoute: onOpenRoute
                )

                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    Label(
                        sessionStore.accounts.count > 1 ? "退出所有账号" : "退出登录",
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
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

private struct MineAccountSwitcherMenu: View {
    @ObservedObject var sessionStore: SessionStore
    let onOpenRoute: (MineOverlayRoute) -> Void

    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Section("切换主账号") {
                ForEach(sessionStore.accounts) { account in
                    Button {
                        selectMainAccount(account.mid)
                    } label: {
                        Label {
                            Text(account.displayName)
                        } icon: {
                            Image(systemName: account.mid == sessionStore.mainAccountMID ? "checkmark.circle.fill" : "person.circle")
                        }
                    }
                }
            }

            Divider()

            Button {
                onOpenRoute(.accountManagement)
            } label: {
                Label("账号管理", systemImage: "person.2")
            }
        } label: {
            HStack(spacing: 8) {
                MineLoggedInHeaderView(
                    avatarURLString: sessionStore.user?.face,
                    username: sessionStore.user?.uname ?? "Logged in",
                    uidText: "UID \(sessionStore.user?.mid ?? 0)"
                )

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("账号操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private func selectMainAccount(_ mid: Int) {
        do {
            try sessionStore.selectMainAccount(mid: mid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

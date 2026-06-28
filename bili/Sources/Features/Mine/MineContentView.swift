import SwiftUI

struct MineContentView: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void

    var body: some View {
        Form {
            MineAccountSection(
                viewModel: viewModel,
                sessionStore: sessionStore,
                onQRCodeLogin: onQRCodeLogin,
                onSMSLogin: onSMSLogin,
                onWebLogin: onWebLogin
            )

            MineAccountLibrarySection(viewModel: viewModel)

            MineSettingsSection(libraryStore: libraryStore)
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
    }
}

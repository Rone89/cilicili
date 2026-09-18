import SwiftUI

struct MineContentView: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var accountMessageViewModel: AccountMessageCenterViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void
    let onOpenRoute: (MineOverlayRoute) -> Void
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        Form {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                normalSections
            } else {
                MineSearchResultsSection(
                    query: searchText,
                    onOpenRoute: onOpenRoute
                )
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded {
            isSearchFocused.wrappedValue = false
        })
    }

    @ViewBuilder
    private var normalSections: some View {
        MineAccountSection(
            viewModel: viewModel,
            sessionStore: sessionStore,
            onQRCodeLogin: onQRCodeLogin,
            onSMSLogin: onSMSLogin,
            onWebLogin: onWebLogin,
            onOpenRoute: onOpenRoute
        )

        MineAccountLibrarySection(
            viewModel: viewModel,
            accountMessageViewModel: accountMessageViewModel,
            isLoggedIn: sessionStore.isLoggedIn,
            onOpenRoute: onOpenRoute
        )

        MineSettingsSection(
            libraryStore: libraryStore,
            onOpenRoute: onOpenRoute
        )
        MineAboutSection()
    }
}

struct MineTabBottomSearchAccessory: View {
    @Binding var text: String
    let onActivate: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(displayText)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: placement == .inline ? 40 : 44)
            .padding(.horizontal, placement == .inline ? 12 : 16)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mine.search.field")
    }

    private var displayText: String {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return placement == .inline ? "搜索" : "搜索我的页功能"
    }
}

struct MineKeyboardSearchAccessory: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("搜索我的页功能", text: $text)
                .focused(isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("mine.search.field")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 16)
        .biliRegularGlassEffect(interactive: true, in: Capsule())
        .task {
            await Task.yield()
            isFocused.wrappedValue = true
        }
    }
}

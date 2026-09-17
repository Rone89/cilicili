import SwiftUI
import UIKit

struct MineContentView: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var accountMessageViewModel: AccountMessageCenterViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void
    let onOpenRoute: (MineOverlayRoute) -> Void
    @State private var searchText = ""

    var body: some View {
        Form {
            Section {
                MineInlineSearchBar(text: $searchText)
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

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

private struct MineInlineSearchBar: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "搜索我的页功能"
        searchBar.searchTextField.backgroundColor = .secondarySystemBackground
        searchBar.searchTextField.autocorrectionType = .no
        searchBar.searchTextField.autocapitalizationType = .none
        searchBar.searchTextField.returnKeyType = .search
        searchBar.searchTextField.accessibilityIdentifier = "mine.search.field"
        searchBar.delegate = context.coordinator
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        context.coordinator.owner = self
        guard searchBar.text != text, searchBar.searchTextField.markedTextRange == nil else { return }
        searchBar.text = text
    }

    final class Coordinator: NSObject, UISearchBarDelegate, UIGestureRecognizerDelegate {
        var owner: MineInlineSearchBar
        private weak var searchBar: UISearchBar?
        private lazy var dismissKeyboardTap: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(dismissKeyboard)
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        init(owner: MineInlineSearchBar) {
            self.owner = owner
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange _: String) {
            owner.text = searchBar.text ?? ""
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            self.searchBar = searchBar
            searchBar.window?.addGestureRecognizer(dismissKeyboardTap)
        }

        func searchBarTextDidEndEditing(_: UISearchBar) {
            dismissKeyboardTap.view?.removeGestureRecognizer(dismissKeyboardTap)
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let searchBar else { return false }
            return touch.view?.isDescendant(of: searchBar) != true
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func dismissKeyboard() {
            searchBar?.resignFirstResponder()
        }
    }
}

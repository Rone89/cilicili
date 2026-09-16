import SwiftUI

struct MineInterfaceSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            MineDisplaySettingsSection(libraryStore: libraryStore)

        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}

struct MineHomeAndSearchSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            MineHomeSettingsSection(libraryStore: libraryStore)
            MineSearchSettingsSection(libraryStore: libraryStore)
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}

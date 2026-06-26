import SwiftUI

struct MineDisplayAndHomeSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            MineDisplaySettingsSection(libraryStore: libraryStore)
            MineRootTabSettingsSection(libraryStore: libraryStore)
            MineHomeSettingsSection(libraryStore: libraryStore)
            MineSearchSettingsSection(libraryStore: libraryStore)
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}

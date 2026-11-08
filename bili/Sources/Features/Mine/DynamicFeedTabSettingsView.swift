import SwiftUI

/// 动态页顶部分段选项的显隐与排序设置。
/// 仅使用系统原生控件：List/Form 行、Toggle、原生编辑（拖动）模式。
struct DynamicFeedTabSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @Environment(\.editMode) private var editMode

    private var visibleKinds: [DynamicFeedKind] {
        libraryStore.visibleDynamicFeedKinds
    }

    private var hiddenKinds: [DynamicFeedKind] {
        DynamicFeedKind.defaultOrder.filter { !visibleKinds.contains($0) }
    }

    private var isEditingOrder: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        Form {
            Section {
                ForEach(visibleKinds, id: \.self) { kind in
                    if isEditingOrder {
                        Text(kind.title)
                            .accessibilityIdentifier("settings.dynamicFeedTabs.row.\(kind.rawValue)")
                    } else {
                        Toggle(
                            kind.title,
                            isOn: visibilityBinding(kind)
                        )
                        .disabled(visibleKinds.count <= 1)
                        .accessibilityIdentifier("settings.dynamicFeedTabs.toggle.\(kind.rawValue)")
                    }
                }
                .onMove(perform: libraryStore.moveDynamicFeedKinds)
            } header: {
                Text("显示的选项")
            } footer: {
                Text(
                    "顶部分段按此顺序显示，至少保留一个选项。点右上角“编辑”后拖动可调整顺序；"
                        + "只保留一个选项时，动态页顶部改为显示「动态」大标题。"
                )
            }

            if !hiddenKinds.isEmpty {
                Section {
                    ForEach(hiddenKinds, id: \.self) { kind in
                        Toggle(
                            kind.title,
                            isOn: visibilityBinding(kind)
                        )
                        .accessibilityIdentifier("settings.dynamicFeedTabs.toggle.\(kind.rawValue)")
                    }
                } header: {
                    Text("已隐藏")
                } footer: {
                    Text("重新开启后，该选项会按默认顺序回到顶部段中。")
                }
            }

            Section {
                Button("恢复默认") {
                    libraryStore.resetDynamicFeedTabs()
                }
                .accessibilityIdentifier("settings.dynamicFeedTabs.reset")
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .accessibilityIdentifier("settings.dynamicFeedTabs.edit")
            }
        }
    }

    private func visibilityBinding(_ kind: DynamicFeedKind) -> Binding<Bool> {
        Binding(
            get: { visibleKinds.contains(kind) },
            set: { libraryStore.setDynamicFeedTab(kind, isVisible: $0) }
        )
    }
}

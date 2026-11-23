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
                Picker(
                    "信息流布局",
                    selection: Binding(
                        get: { libraryStore.dynamicFeedLayoutMode },
                        set: { libraryStore.setDynamicFeedLayoutMode($0) }
                    )
                ) {
                    ForEach(DynamicFeedLayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .accessibilityIdentifier("settings.dynamicFeedTabs.layoutMode")

                Toggle(
                    "卡片阴影",
                    isOn: Binding(
                        get: { libraryStore.showsDynamicMultiColumnCardShadow },
                        set: { libraryStore.setShowsDynamicMultiColumnCardShadow($0) }
                    )
                )
                .accessibilityIdentifier("settings.dynamicFeedTabs.cardShadow")
            } header: {
                Text("布局模式")
            } footer: {
                Text("瀑布流与等高网格模式在 iPhone、iPhone Duo 与 iPad 上均可开启，会根据屏幕宽度自动调整为 2 至 5 列；等高网格统一按 16:9 视频卡片尺寸排布，超出比例的预览图居中裁切。卡片阴影仅作用于瀑布流与等高网格。")
            }

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

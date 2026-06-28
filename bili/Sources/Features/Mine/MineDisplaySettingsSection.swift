import SwiftUI

struct MineDisplaySettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("显示") {
            Picker(selection: Binding(
                get: { libraryStore.appearanceMode },
                set: { libraryStore.setAppearanceMode($0) }
            )) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("外观", systemImage: "circle.lefthalf.filled")
            }
            .tint(libraryStore.appTintColor)

            MineThemeColorControl(libraryStore: libraryStore)

            Toggle(isOn: Binding(
                get: { libraryStore.minimizesTabBarOnScroll },
                set: { libraryStore.setMinimizesTabBarOnScroll($0) }
            )) {
                Label("滑动时缩小底部 Tab", systemImage: "arrow.down.right.and.arrow.up.left")
            }

            Picker(selection: Binding(
                get: { libraryStore.scrollEdgeEffectPreference },
                set: { libraryStore.setScrollEdgeEffectPreference($0) }
            )) {
                ForEach(AppScrollEdgeEffectPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                Label("滚动边缘效果", systemImage: "rectangle.topthird.inset.filled")
            }
            .pickerStyle(.navigationLink)

            Toggle(isOn: Binding(
                get: { libraryStore.force120HzScrollingEnabled },
                set: { libraryStore.setForce120HzScrollingEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("强制滑动 120Hz 刷新率", systemImage: "speedometer")

                    Text("开启后滑动会强制使用 120Hz，可能会引起耗电增加，请谨慎开启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MineThemeColorControl: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var selectionMode: ThemeColorSelectionMode = .tone
    @State private var tintHexDraft = ""

    private let swatchHexes = AppThemeTintColor.toneHexes
    private let swatchColumns = Array(repeating: GridItem(.fixed(32), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("主色调", systemImage: "paintpalette")

            Picker("选择方式", selection: $selectionMode) {
                ForEach(ThemeColorSelectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            selectedModeContent

            currentSelectionFooter

            Text("影响 App 选中状态、系统控件高亮和首页点击刷新颜色。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            tintHexDraft = libraryStore.appTintColorHex
            selectionMode = mode(for: libraryStore.appTintColorHex)
        }
        .onChange(of: libraryStore.appTintColorHex) { _, hex in
            tintHexDraft = hex
        }
        .tint(libraryStore.appTintColor)
    }

    @ViewBuilder
    private var selectedModeContent: some View {
        switch selectionMode {
        case .tone:
            LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: 12) {
                ForEach(swatchHexes, id: \.self) { hex in
                    Button {
                        libraryStore.setAppTintColorHex(hex)
                        tintHexDraft = libraryStore.appTintColorHex
                    } label: {
                        colorSwatch(hex)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择颜色 \(hex)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .palette:
            VStack(alignment: .leading, spacing: 10) {
                ColorPicker(
                    selection: Binding(
                        get: { libraryStore.appTintColor },
                        set: { color in
                            libraryStore.setAppTintColor(color)
                            tintHexDraft = libraryStore.appTintColorHex
                        }
                    ),
                    supportsOpacity: false
                ) {
                    Label("直接从色板选", systemImage: "eyedropper.full")
                }

                HStack(spacing: 10) {
                    TextField(AppThemeTintColor.defaultHex, text: $tintHexDraft)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit(commitDraftHex)

                    Button {
                        commitDraftHex()
                    } label: {
                        Label("应用", systemImage: "checkmark.circle")
                    }
                    .disabled(normalizedDraftHex == nil)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var currentSelectionFooter: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(libraryStore.appTintColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(Color(.separator).opacity(0.30), lineWidth: 0.8)
                }

            Text(libraryStore.appTintColorHex)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button("恢复默认") {
                libraryStore.resetAppTintColor()
                tintHexDraft = libraryStore.appTintColorHex
                selectionMode = .tone
            }
            .buttonStyle(.borderless)
        }
    }

    private var normalizedDraftHex: String? {
        AppThemeTintColor.normalizedHex(tintHexDraft)
    }

    private func commitDraftHex() {
        guard let normalizedDraftHex else { return }
        libraryStore.setAppTintColorHex(normalizedDraftHex)
        tintHexDraft = libraryStore.appTintColorHex
    }

    private func mode(for hex: String) -> ThemeColorSelectionMode {
        swatchHexes.contains(hex) ? .tone : .palette
    }

    private func colorSwatch(_ hex: String) -> some View {
        let color = AppThemeTintColor.color(for: hex)
        let isSelected = libraryStore.appTintColorHex == hex
        return Circle()
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle()
                    .stroke(Color(.separator).opacity(0.30), lineWidth: 0.8)
            }
    }
}

private enum ThemeColorSelectionMode: String, CaseIterable, Identifiable {
    case tone
    case palette

    var id: Self { self }

    var title: String {
        switch self {
        case .tone:
            "色调"
        case .palette:
            "色板"
        }
    }
}

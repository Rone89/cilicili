import SwiftUI

struct MineDisplaySettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("显示") {
            Picker(
                selection: Binding(
                    get: { libraryStore.appearanceMode },
                    set: { libraryStore.setAppearanceMode($0) }
                )
            ) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                MineSettingsLabel("外观", systemImage: "sun.max")
            }
            .tint(libraryStore.appTintColor)
            .pickerStyle(.menu)

            Picker(
                selection: Binding(
                    get: { libraryStore.appIconPreference },
                    set: { libraryStore.setAppIconPreference($0) }
                )
            ) {
                ForEach(AppIconPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                MineSettingsLabel("应用图标", systemImage: "app")
            }
            .pickerStyle(.menu)

            MineThemeColorControl(libraryStore: libraryStore)

            Toggle(
                isOn: Binding(
                    get: { libraryStore.followsSystemFontSize },
                    set: { libraryStore.setFollowsSystemFontSize($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("使用系统字号", systemImage: "textformat.size")

                    Text("关闭后可固定整个 App 的字号，不再随系统文字大小变化。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !libraryStore.followsSystemFontSize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        MineSettingsLabel("固定 App 字号", systemImage: "textformat")
                        Spacer(minLength: 8)
                        Text(libraryStore.manualFontSize.title)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: manualFontSizeBinding,
                        in: 0...Double(AppManualFontSize.allCases.count - 1),
                        step: 1
                    ) {
                        Text("固定 App 字号")
                    } minimumValueLabel: {
                        Text("A").font(.caption2)
                    } maximumValueLabel: {
                        Text("A").font(.title3)
                    }
                    .tint(libraryStore.appTintColor)
                    .accessibilityValue(libraryStore.manualFontSize.title)
                }
            }

            Picker(
                selection: Binding(
                    get: { libraryStore.remoteImageQualityPreference },
                    set: { libraryStore.setRemoteImageQualityPreference($0) }
                )
            ) {
                ForEach(RemoteImageQualityPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("图片质量", systemImage: "photo")

                    Text(libraryStore.remoteImageQualityPreference.detail)
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)

            Toggle(
                isOn: Binding(
                    get: { libraryStore.showsVideoCoverDurationBadges },
                    set: { libraryStore.setShowsVideoCoverDurationBadges($0) }
                )
            ) {
                MineSettingsLabel("显示视频封面时长", systemImage: "timer")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.minimizesTabBarOnScroll },
                    set: { libraryStore.setMinimizesTabBarOnScroll($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("滚动时最小化 TabBar", systemImage: "arrow.down.right.and.arrow.up.left")

                    Text("关闭后底部 TabBar 会始终保持完整高度。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker(
                selection: Binding(
                    get: { libraryStore.videoDetailSegmentedPickerGlassStyle },
                    set: { libraryStore.setVideoDetailSegmentedPickerGlassStyle($0) }
                )
            ) {
                ForEach(VideoDetailSegmentedPickerGlassStyle.allCases) { glassStyle in
                    Text(glassStyle.title).tag(glassStyle)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("底部栏 Liquid Glass 材质", systemImage: "circle.lefthalf.filled")

                    Text("选择视频详情页底部切换器的清透或常规材质。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)

            Picker(
                selection: Binding(
                    get: { libraryStore.videoDetailActionButtonStyle },
                    set: { libraryStore.setVideoDetailActionButtonStyle($0) }
                )
            ) {
                ForEach(VideoDetailActionButtonStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("详情页操作按钮样式", systemImage: "hand.tap")

                    Text("可选择普通按钮或液态玻璃按钮，默认使用普通按钮。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)

            Toggle(
                isOn: Binding(
                    get: { libraryStore.force120HzScrollingEnabled },
                    set: { libraryStore.setForce120HzScrollingEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("强制 120Hz 滚动", systemImage: "speedometer")

                    Text("在支持高刷新率的 iPhone 上锁定 120Hz 滚动，可能增加耗电。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var manualFontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(libraryStore.manualFontSize.rawValue) },
            set: { value in
                guard let size = AppManualFontSize(rawValue: Int(value.rounded())) else { return }
                libraryStore.setManualFontSize(size)
            }
        )
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
            MineSettingsLabel("主色调", systemImage: "paintpalette")

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
                    MineSettingsLabel("直接从色板选", systemImage: "eyedropper")
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
                        MineSettingsLabel("应用", systemImage: "checkmark.circle")
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

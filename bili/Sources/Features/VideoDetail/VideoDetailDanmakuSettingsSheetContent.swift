import SwiftUI

struct DanmakuSettingsSheetContent: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let summary: String
    let hidesDanmakuInPortraitBinding: Binding<Bool>
    let toggleDanmaku: () -> Void
    let updateDanmakuSettings: (DanmakuSettings) -> Void

    var body: some View {
        // 去掉表单默认的分组灰黑卡片底色：让弹窗统一透出底部玻璃材质，
        // 不再出现一块块深色方块。
        Form {
            DanmakuSettingsHeaderFormSection(
                store: store,
                summary: summary,
                toggleDanmaku: toggleDanmaku
            )
            .listRowBackground(Color.clear)

            DanmakuSettingsPortraitVisibilitySection(
                hidesDanmakuInPortrait: hidesDanmakuInPortraitBinding
            )
            .listRowBackground(Color.clear)

            DanmakuKitSettingsSection(
                settings: store.danmakuSettings,
                updateSettings: updateDanmakuSettings
            )
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
    }
}

struct DanmakuKitSettingsSection: View {
    let settings: DanmakuSettings
    let updateSettings: (DanmakuSettings) -> Void

    var body: some View {
        Section("DanmakuKit 渲染设置") {
            DanmakuKitSettingsContent(settings: settings, updateSettings: updateSettings)
                .listRowBackground(Color.clear)
        }
    }
}

struct DanmakuKitSettingsContent: View {
    let settings: DanmakuSettings
    let updateSettings: (DanmakuSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("显示区域")
                    Spacer()
                    Text(settings.danmakuKit.displayArea.title)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("重置") {
                        updateKitSettings { $0.displayArea = .topHalf }
                    }
                    .accessibilityLabel("重置 DanmakuKit 显示区域为 50%")
                }
                Slider(
                    value: Binding(
                        get: { settings.danmakuKit.displayArea.fraction },
                        set: { value in
                            updateKitSettings { $0.displayArea = DanmakuDisplayArea(fraction: value) }
                        }
                    ),
                    in: 0.1...1.0,
                    step: 0.1
                )
                .accessibilityLabel("DanmakuKit 弹幕显示区域")
            }

            Toggle("海量弹幕（轨道满时仍显示）", isOn: boolBinding(\.allowsDanmakuOverlap))
            Text(
                settings.danmakuKit.allowsDanmakuOverlap
                    ? "轨道占满时继续显示滚动弹幕，可能出现遮挡。"
                    : "轨道占满时跳过无法安全排布的弹幕。"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            DanmakuSettingsSlider(
                title: "字体大小",
                systemImage: "textformat.size",
                value: doubleBinding(\.fontScale),
                range: 0.7...1.45,
                step: 0.05,
                valueText: "\(Int((settings.danmakuKit.fontScale * 100).rounded()))%"
            )

            // 菜单式选择器：横屏“更多”抽屉是自绘面板、没有 NavigationStack，
            // navigationLink 风格需要导航栈才能推子页，横屏下会异常（被转回竖屏）。
            Picker(selection: enumBinding(\.fontWeight)) {
                ForEach(DanmakuFontWeightOption.allCases) { weight in
                    Text(weight.title).tag(weight)
                }
            } label: {
                Label("字体粗细", systemImage: "bold")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ui.danmakuKit.settings.fontWeight")

            DanmakuSettingsSlider(
                title: "不透明度",
                systemImage: "circle.lefthalf.filled",
                value: doubleBinding(\.opacity),
                range: 0.25...1.0,
                step: 0.05,
                valueText: "\(Int((settings.danmakuKit.opacity * 100).rounded()))%"
            )

            Toggle("滚动弹幕", isOn: boolBinding(\.enablesFloating))
                .accessibilityIdentifier("ui.danmakuKit.settings.floating")
            Toggle("顶部弹幕", isOn: boolBinding(\.enablesTop))
                .accessibilityIdentifier("ui.danmakuKit.settings.top")
            Toggle("底部弹幕", isOn: boolBinding(\.enablesBottom))
                .accessibilityIdentifier("ui.danmakuKit.settings.bottom")

            DanmakuSettingsSlider(
                title: "轨道高度",
                systemImage: "rectangle.stack",
                value: doubleBinding(\.trackHeight),
                range: 22...60,
                step: 2,
                valueText: "\(Int(settings.danmakuKit.trackHeight.rounded())) pt"
            )
            .accessibilityIdentifier("ui.danmakuKit.settings.trackHeight")

            DanmakuSettingsSlider(
                title: "顶部轨道留白",
                systemImage: "arrow.up.to.line",
                value: doubleBinding(\.topPadding),
                range: 0...100,
                step: 4,
                valueText: "\(Int(settings.danmakuKit.topPadding.rounded())) pt"
            )
            .accessibilityIdentifier("ui.danmakuKit.settings.topPadding")

            DanmakuSettingsSlider(
                title: "底部轨道留白",
                systemImage: "arrow.down.to.line",
                value: doubleBinding(\.bottomPadding),
                range: 0...100,
                step: 4,
                valueText: "\(Int(settings.danmakuKit.bottomPadding.rounded())) pt"
            )
            .accessibilityIdentifier("ui.danmakuKit.settings.bottomPadding")

            Text("显示区域、密度、字号、字重和不透明度均由 DanmakuKit 弹幕模型渲染；速度自动跟随视频倍速，轨道留白会叠加播放器控件避让区域。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func boolBinding(
        _ keyPath: WritableKeyPath<DanmakuKitRenderSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings.danmakuKit[keyPath: keyPath] },
            set: { newValue in updateKitSettings { $0[keyPath: keyPath] = newValue } }
        )
    }
    private func doubleBinding(
        _ keyPath: WritableKeyPath<DanmakuKitRenderSettings, Double>
    ) -> Binding<Double> {
        Binding(
            get: { settings.danmakuKit[keyPath: keyPath] },
            set: { newValue in updateKitSettings { $0[keyPath: keyPath] = newValue } }
        )
    }
    private func enumBinding<Value: Hashable>(
        _ keyPath: WritableKeyPath<DanmakuKitRenderSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings.danmakuKit[keyPath: keyPath] },
            set: { newValue in updateKitSettings { $0[keyPath: keyPath] = newValue } }
        )
    }
    private func updateKitSettings(_ update: (inout DanmakuKitRenderSettings) -> Void) {
        var nextSettings = settings
        var kitSettings = nextSettings.danmakuKit
        update(&kitSettings)
        nextSettings.danmakuKit = kitSettings
        updateSettings(nextSettings)
    }
}

struct DanmakuSettingsPortraitVisibilitySection: View {
    @Binding var hidesDanmakuInPortrait: Bool

    var body: some View {
        Section("竖屏播放") {
            DanmakuSettingsPortraitVisibilityContent(hidesDanmakuInPortrait: $hidesDanmakuInPortrait)
                .listRowBackground(Color.clear)
        }
    }
}

struct DanmakuSettingsPortraitVisibilityContent: View {
    @Binding var hidesDanmakuInPortrait: Bool

    var body: some View {
        Toggle("竖屏时隐藏弹幕", isOn: $hidesDanmakuInPortrait)
            .accessibilityIdentifier("ui.videoDetail.sheet.danmakuSettings.hidesInPortrait")
    }
}

/// 横屏设置抽屉里的弹幕设置子页：复用一级页的卡片容器（12pt 内边距、圆角 14）。
struct DanmakuSettingsLandscapePanelContent: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let summary: String
    let hidesDanmakuInPortraitBinding: Binding<Bool>
    let toggleDanmaku: () -> Void
    let updateDanmakuSettings: (DanmakuSettings) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                card {
                    DanmakuSettingsHeaderSectionContent(
                        isDanmakuEnabled: store.isDanmakuEnabled,
                        settings: store.danmakuSettings,
                        summary: summary,
                        toggleDanmaku: toggleDanmaku
                    )
                }

                sectionHeader("竖屏播放")
                card {
                    DanmakuSettingsPortraitVisibilityContent(
                        hidesDanmakuInPortrait: hidesDanmakuInPortraitBinding
                    )
                }

                sectionHeader("DanmakuKit 渲染设置")
                card {
                    DanmakuKitSettingsContent(
                        settings: store.danmakuSettings,
                        updateSettings: updateDanmakuSettings
                    )
                }
            }
            .padding(12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

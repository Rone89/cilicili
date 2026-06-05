import SwiftUI

struct DanmakuSettingsSheet: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let toggleDanmaku: () -> Void
    let updateDanmakuSettings: (DanmakuSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Label("弹幕", systemImage: store.isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(store.isDanmakuEnabled ? .pink : .secondary)

                            Spacer(minLength: 8)

                            Toggle(
                                "启用弹幕",
                                isOn: Binding(
                                    get: { store.isDanmakuEnabled },
                                    set: { isEnabled in
                                        if store.isDanmakuEnabled != isEnabled {
                                            toggleDanmaku()
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                        }

                        Text(settingsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            DanmakuSettingsChip(title: store.danmakuSettings.displayArea.title, systemImage: "rectangle.inset.filled")
                            DanmakuSettingsChip(title: "\(Int((store.danmakuSettings.fontScale * 100).rounded()))%", systemImage: "textformat.size")
                            DanmakuSettingsChip(title: "\(Int((store.danmakuSettings.opacity * 100).rounded()))%", systemImage: "circle.lefthalf.filled")
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("显示区域") {
                    Picker("覆盖范围", selection: displayAreaBinding) {
                        ForEach(DanmakuDisplayArea.allCases) { area in
                            Text(area.title).tag(area)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }

                Section("文字") {
                    settingSlider(
                        title: "字体大小",
                        systemImage: "textformat.size",
                        value: fontScaleBinding,
                        range: 0.7...1.45,
                        step: 0.05,
                        valueText: "\(Int((store.danmakuSettings.fontScale * 100).rounded()))%"
                    )

                    Picker(selection: fontWeightBinding) {
                        ForEach(DanmakuFontWeightOption.allCases) { weight in
                            Text(weight.title).tag(weight)
                        }
                    } label: {
                        Label("字体粗细", systemImage: "bold")
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("透明度") {
                    settingSlider(
                        title: "不透明度",
                        systemImage: "circle.lefthalf.filled",
                        value: opacityBinding,
                        range: 0.25...1.0,
                        step: 0.05,
                        valueText: "\(Int((store.danmakuSettings.opacity * 100).rounded()))%"
                    )
                }
            }
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var settingsSummary: String {
        if store.isDanmakuEnabled {
            return "当前使用 \(store.danmakuSettings.displayArea.title)，字号 \(Int((store.danmakuSettings.fontScale * 100).rounded()))%，不透明度 \(Int((store.danmakuSettings.opacity * 100).rounded()))%。"
        }
        return "弹幕已关闭，播放时不会显示滚动评论。"
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { store.danmakuSettings.fontScale },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.fontScale = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { store.danmakuSettings.opacity },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.opacity = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    private var displayAreaBinding: Binding<DanmakuDisplayArea> {
        Binding(
            get: { store.danmakuSettings.displayArea },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.displayArea = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    private var fontWeightBinding: Binding<DanmakuFontWeightOption> {
        Binding(
            get: { store.danmakuSettings.fontWeight },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.fontWeight = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    private func settingSlider(
        title: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }
}

private struct DanmakuSettingsChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
            }
    }
}

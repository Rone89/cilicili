import SwiftUI

/// 控制条字幕（CC）按钮：仅有字幕轨时显示，挂在 accessory 槽位。
struct VideoDetailSubtitleControlButton: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    let metrics: PlayerNativeControlMetrics
    let onSelect: () -> Void

    var body: some View {
        if store.hasTracks {
            PlayerNativeGlassIconButton(
                systemName: store.selectedLan == nil ? "captions.bbox" : "captions.bbox.fill",
                accessibilityLabel: "字幕",
                accessibilityIdentifier: "ui.player.subtitle.toggle",
                metrics: metrics,
                action: onSelect
            )
        }
    }
}

/// 字幕轨选择弹层（控制条 CC 按钮入口）。
struct VideoDetailSubtitleSelectionSheet: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    let onSelect: (String?) -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    close()
                } label: {
                    HStack {
                        Label("关闭字幕", systemImage: "captions.bbox.slash")
                        Spacer()
                        if store.selectedLan == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                ForEach(store.tracks) { track in
                    Button {
                        onSelect(track.lan)
                        close()
                    } label: {
                        HStack {
                            Text(track.lanDoc)
                            if track.isAI {
                                Text("AI")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .foregroundStyle(.tint)
                            }
                            Spacer()
                            if store.selectedLan == track.lan {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if let message = store.loadErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("字幕")
            .navigationBarTitleDisplayMode(.inline)
            .foregroundStyle(.primary)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

import SwiftUI

struct LivePlayerAccessory: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                LiveQualityMenu(viewModel: viewModel)
                LiveStreamMenu(viewModel: viewModel)
                Spacer(minLength: 0)
                LiveDanmakuToggleButton(viewModel: viewModel)
                LiveDanmakuDiagnosticsButton(viewModel: viewModel)
            }
        }
    }
}

struct LiveStreamMenu: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        if viewModel.hasMultipleStreamCandidates || viewModel.currentStreamTitle != nil {
            Menu {
                ForEach(viewModel.streamMenuItems) { item in
                    Button {
                        viewModel.selectStreamCandidate(id: item.id)
                    } label: {
                        if item.isSelected {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                Label(viewModel.currentStreamTitle ?? "线路", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .biliPlayerGlassButtonStyle()
            .foregroundStyle(.white)
        }
    }
}

struct LiveQualityMenu: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        if viewModel.hasMultipleQualities || viewModel.currentQualityTitle != nil {
            Menu {
                ForEach(viewModel.qualityMenuItems) { item in
                    Button {
                        viewModel.selectQuality(qn: item.qn)
                    } label: {
                        if item.isSelected {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                Label(viewModel.currentQualityTitle ?? "画质", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .biliPlayerGlassButtonStyle()
            .foregroundStyle(.white)
        }
    }
}

private struct LiveDanmakuToggleButton: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        Button {
            viewModel.toggleDanmaku()
        } label: {
            Label(
                viewModel.isDanmakuEnabled ? "弹幕开" : "弹幕关",
                systemImage: viewModel.isDanmakuEnabled ? "text.bubble.fill" : "text.bubble"
            )
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .biliPlayerGlassButtonStyle(prominent: viewModel.isDanmakuEnabled)
        .tint(viewModel.isDanmakuEnabled ? .white : .secondary)
        .accessibilityLabel(viewModel.isDanmakuEnabled ? "关闭直播弹幕" : "开启直播弹幕")
    }
}

private struct LiveDanmakuDiagnosticsButton: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        Button {
            viewModel.toggleLiveDanmakuDiagnostics()
        } label: {
            Label(
                viewModel.isLiveDanmakuDiagnosticsEnabled ? "诊断开" : "诊断",
                systemImage: "waveform.path.ecg"
            )
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .biliPlayerGlassButtonStyle(prominent: viewModel.isLiveDanmakuDiagnosticsEnabled)
        .tint(viewModel.isLiveDanmakuDiagnosticsEnabled ? .white : .secondary)
        .accessibilityLabel(viewModel.isLiveDanmakuDiagnosticsEnabled ? "关闭直播弹幕诊断" : "开启直播弹幕诊断")
    }
}

import SwiftUI
import UIKit

struct PlayerPerformanceOverlayHeaderRow: View {
    let metricsID: String
    let copyText: String?
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.caption2.weight(.bold))
            Text("播放性能")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 8)
            Text(PlayerPerformanceOverlayFormatting.shortMetricsID(metricsID))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if let copyText {
                Button {
                    UIPasteboard.general.string = copyText
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(didCopy ? .green : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy ? "已复制测试结果" : "复制测试结果")
            }
        }
    }
}

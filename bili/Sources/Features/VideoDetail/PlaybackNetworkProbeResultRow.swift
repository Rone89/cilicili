import SwiftUI

struct PlaybackNetworkProbeResultRow: View {
    let result: PlaybackCDNProbeResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.didSucceed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(result.didSucceed ? .green : .secondary)
            Text(result.preference.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let addressFamily = result.addressFamily {
                Text(addressFamily.title)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Text(result.elapsedMilliseconds.map { "\($0) ms" } ?? result.errorDescription ?? "失败")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

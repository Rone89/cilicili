import SwiftUI

struct PlaybackNetworkBaselineStartupMessageRows: View {
    let session: PlayerPerformanceSession

    var body: some View {
        PlaybackNetworkOptionalMultilineRow(title: "首帧分段", value: session.startupBreakdownMessage)
        PlaybackNetworkOptionalMultilineRow(title: "HLS 启动请求", value: session.hlsStartupMessage)
        PlaybackNetworkOptionalMultilineRow(title: "启动决策", value: session.startupDecisionMessage)
        PlaybackNetworkOptionalMultilineRow(title: "升档结果", value: session.startupUpgradeMessage)
    }
}

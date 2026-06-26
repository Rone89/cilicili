import SwiftUI

struct PlaybackNetworkProbeSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("最近测速") {
            if let snapshot = libraryStore.playbackCDNProbeSnapshotForCurrentContext {
                PlaybackNetworkDiagnosticRow(
                    title: "测速时间",
                    value: snapshot.probedAt.formatted(date: .abbreviated, time: .shortened)
                )
                PlaybackNetworkDiagnosticRow(
                    title: "有效状态",
                    value: isPlaybackCDNProbeSnapshotExpired(snapshot) ? "已过期" : "有效"
                )
                PlaybackNetworkDiagnosticRow(
                    title: "测速参考",
                    value: snapshot.recommendedPreference?.title ?? "暂无参考"
                )

                if let recommendation = snapshot.recommendedPreference,
                   let result = snapshot.result(for: recommendation) {
                    PlaybackNetworkDiagnosticRow(
                        title: "参考延迟",
                        value: result.elapsedMilliseconds.map { "\($0) ms" } ?? "失败"
                    )
                }

                if !snapshot.successfulResults.isEmpty {
                    DisclosureGroup {
                        ForEach(snapshot.results.prefix(8)) { result in
                            PlaybackNetworkProbeResultRow(result: result)
                        }
                    } label: {
                        Label("测速排行", systemImage: "list.number")
                    }
                }

                if isPlaybackCDNProbeSnapshotExpired(snapshot) {
                    Label("测速结果超过 \(playbackCDNProbeRefreshIntervalTitle)，自动 CDN 可能需要重新测速。", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ContentUnavailableView(
                    "暂无 CDN 测速结果",
                    systemImage: "network.slash",
                    description: Text("进入我的页面执行一次 CDN 测速后，这里会显示推荐节点和延迟。")
                )
            }
        }
    }

}

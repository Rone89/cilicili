import SwiftUI

extension MinePlaybackSettingsView {
    var activePlaybackCDNProbeSnapshot: PlaybackCDNProbeSnapshot? {
        if !playbackCDNProbeResults.isEmpty {
            return PlaybackCDNProbeSnapshot(
                probedAt: Date(),
                recommendedPreference: playbackCDNProbeResults.first {
                    $0.didSucceed && $0.elapsedMilliseconds != nil
                }?.preference,
                results: playbackCDNProbeResults
            )
        }
        return libraryStore.playbackCDNProbeSnapshotForCurrentContext
    }

    var playbackCDNProbeRefreshIntervalTitle: String {
        let minutes = libraryStore.playbackCDNProbeRefreshIntervalMinutes
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }

    @ViewBuilder
    var playbackCDNProbeSummary: some View {
        if let snapshot = activePlaybackCDNProbeSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                if let recommendation = snapshot.recommendedPreference,
                   let result = snapshot.result(for: recommendation),
                   let elapsed = result.elapsedMilliseconds {
                    HStack {
                        Label(recommendation.title, systemImage: "checkmark.seal")
                        Spacer()
                        Text("\(elapsed) ms")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("上次测速 \(snapshot.probedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(isPlaybackCDNProbeSnapshotExpired(snapshot) ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))

                if libraryStore.playbackCDNPreference == .automatic,
                   let activeRecommendation = libraryStore.automaticPlaybackCDNRecommendation {
                    Label("测速参考 \(activeRecommendation.title)", systemImage: "bolt.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let avoidanceDescription = libraryStore.activePlaybackCDNAvoidanceDescription {
                    Label("临时避让 \(avoidanceDescription)", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if libraryStore.playbackNetworkAddressFamilyPreference != .automatic {
                    Label("协议偏好 \(libraryStore.playbackNetworkAddressFamilyPreference.title)", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if isPlaybackCDNProbeSnapshotExpired(snapshot) {
                    Label("CDN 测速结果已超过 \(playbackCDNProbeRefreshIntervalTitle)，建议重新测速", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                DisclosureGroup(isExpanded: $isShowingPlaybackCDNProbeDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.results) { result in
                            playbackCDNProbeResultRow(result)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("CDN 测速排行", systemImage: "list.number")
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    func playbackCDNProbeResultRow(_ result: PlaybackCDNProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(result.preference.title)
                    .lineLimit(1)
                Spacer()
                if result.didSucceed, let elapsed = result.elapsedMilliseconds {
                    Text("\(elapsed) ms")
                        .monospacedDigit()
                } else if let elapsed = result.elapsedMilliseconds {
                    Text("失败 · \(elapsed) ms")
                        .monospacedDigit()
                } else {
                    Text("失败")
                }
            }
            .font(.caption)

            if let failureReason = result.failureReason {
                Label(failureReason, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(result.didSucceed ? .secondary : .tertiary)
    }

    func isPlaybackCDNProbeSnapshotExpired(_ snapshot: PlaybackCDNProbeSnapshot) -> Bool {
        snapshot.isExpired(freshnessInterval: libraryStore.playbackCDNProbeRefreshInterval)
    }
}

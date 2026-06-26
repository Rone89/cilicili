import SwiftUI

struct PlayerPerformanceLogView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var store = PlayerPerformanceStore.shared

    var body: some View {
        List {
            if store.events.isEmpty && store.sessions.isEmpty {
                ContentUnavailableView(
                    "暂无播放记录",
                    systemImage: "speedometer",
                    description: Text("播放自动优化会在后台使用这些记录调整开播画质、预加载和 CDN 复测。")
                )
            } else {
                Section("自动优化") {
                    PlayerAutoOptimizationSummaryRow(
                        profile: store.playbackAdaptationProfile(
                            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
                        )
                    )
                }

                let sampleGroups = store.startupSampleGroups()
                if !sampleGroups.isEmpty {
                    Section("启动样本") {
                        ForEach(Array(sampleGroups.enumerated()), id: \.element.id) { index, group in
                            PlayerPerformanceSampleGroupRow(group: group, isRecommended: index == 0)
                        }
                    }
                }

                if !store.sessions.isEmpty {
                    let exceptionSessions = store.sessions.filter {
                        $0.failureMessage != nil
                            || $0.bufferCount >= 2
                            || $0.seekCount >= 12
                            || $0.resumeRecoverySlowCount > 0
                            || $0.seekRecoverySlowCount > 0
                            || ($0.accessLogStallCount ?? 0) > 0
                    }
                    if !exceptionSessions.isEmpty {
                        Section("最近异常") {
                            ForEach(exceptionSessions.prefix(5)) { session in
                                PlayerPerformanceExceptionRow(session: session)
                            }
                        }
                    }

                    Section("最近视频") {
                        ForEach(store.sessions) { session in
                            PlayerPerformanceSessionRow(session: session)
                        }
                    }
                }

                Section {
                    ForEach(store.events.reversed()) { event in
                        PlayerPerformanceEventRow(event: event)
                    }
                } header: {
                    Text("最近 \(store.events.count) 条")
                }
            }
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空") {
                    store.clear()
                }
                .disabled(store.events.isEmpty)
            }
        }
    }
}

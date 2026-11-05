import QuartzCore

/// 自动化诊断用的播放显示/弹幕策略开关；正常启动时保持默认值。
@MainActor
enum PlaybackDiagnosticsExperiment {
    /// HDR 播放时把输出动态范围限制到 constrainedHigh（保留 HDR，降低合成开销）。
    static var constrainedHighHDR = false
    /// 弹幕叠加层强制进入 load shedding（30fps + 降低数量）。
    static var forceDanmakuLoadShedding = false
    /// 强制使用 Metal 弹幕渲染器（覆盖 HDR 自动回退）。
    static var forceMetalDanmaku = false
    /// 强制使用 DanmakuKit（即使当前为 HDR）。
    static var forceDanmakuKit = false
    /// 禁用本地代理的"边下边播"流式返回，改为整段下载后返回。
    static var forceNonStreamingRanges = false
    /// 显示策略变化时由引擎重新应用到当前播放层。
    static var onDisplayPolicyChange: (() -> Void)?

    static func reset() {
        constrainedHighHDR = false
        forceDanmakuLoadShedding = false
        forceMetalDanmaku = false
        forceDanmakuKit = false
        forceNonStreamingRanges = false
    }
}

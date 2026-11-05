import UIKit

/// 供自动化诊断定位当前视频详情播放器（弱引用，不参与生命周期）。
@MainActor
enum VideoDetailPlaybackLocator {
    static weak var currentViewModel: VideoDetailViewModel?
}

/// 由启动参数 `--hitch-self-test` 触发的 HDR 播放卡顿自测。
///
/// 依次执行：HDR 不滚动 → HDR 滚动 → HDR 关弹幕滚动 → 1080P 滚动 → 1080P 关弹幕滚动，
/// 每个阶段 20 秒，并在诊断日志写入阶段标记；卡顿探针会带上 `phase=` 字段。
/// 仅在显式传入启动参数时运行，正常启动无任何行为变化。
@MainActor
final class PlaybackHitchSelfTest {
    static let shared = PlaybackHitchSelfTest()

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--hitch-self-test")
    }

    private var hasStarted = false
    private var libraryStore: LibraryStore?
    private let phaseDuration: TimeInterval = 20
    private let phaseCount = 6

    private init() {}

    func startIfRequested(libraryStore: LibraryStore) {
        guard Self.isRequested, !hasStarted else { return }
        hasStarted = true
        self.libraryStore = libraryStore
        Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        mark("waiting")
        guard let viewModel = await waitForViewModel(timeout: 45) else {
            mark("failed reason=noViewModel")
            return
        }
        guard await waitForPlayback(viewModel, timeout: 30) else {
            mark("failed reason=noPlayback")
            return
        }
        // `--hitch-mode off|kit|metal`：每次启动只固定一种弹幕配置，避免运行时切换污染数据。
        let mode = Self.argumentValue(after: "--hitch-mode") ?? "off"
        PlaybackDiagnosticsExperiment.reset()
        switch mode {
        case "kit":
            PlaybackDiagnosticsExperiment.forceDanmakuKit = true
            libraryStore?.setDanmakuEnabled(true)
            viewModel.isDanmakuEnabled = true
        case "metal":
            PlaybackDiagnosticsExperiment.forceMetalDanmaku = true
            libraryStore?.setDanmakuEnabled(true)
            viewModel.isDanmakuEnabled = true
        case "nostream":
            libraryStore?.setDanmakuEnabled(false)
            viewModel.isDanmakuEnabled = false
            PlaybackDiagnosticsExperiment.forceNonStreamingRanges = true
        default:
            libraryStore?.setDanmakuEnabled(false)
            viewModel.isDanmakuEnabled = false
        }
        let targetQuality = (mode == "sdr" || mode == "nostream") ? 112 : 125
        await selectQuality(targetQuality, viewModel: viewModel)
        _ = await waitForPlayback(viewModel, timeout: 25)
        if let progressText = Self.argumentValue(after: "--hitch-progress"),
           let progress = Double(progressText) {
            viewModel.stablePlayerViewModel?.seek(to: min(max(progress, 0), 0.98))
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        for index in 1...phaseCount {
            await runPhase(
                "\(mode)_\(index)",
                scroll: false
            )
        }
        mark("done mode=\(mode)")
        PlaybackDiagnosticsExperiment.reset()
        PlaybackHitchMonitor.shared.setSelfTestPhase("-")
    }

    private func runPhase(_ name: String, scroll: Bool) async {
        PlaybackHitchMonitor.shared.setSelfTestPhase(name)
        mark("\(name)_measuring")
        if scroll {
            await DetailScrollDriver.scroll(duration: phaseDuration)
        } else {
            try? await Task.sleep(nanoseconds: UInt64(phaseDuration * 1_000_000_000))
        }
        mark("\(name)_end")
        PlaybackHitchMonitor.shared.setSelfTestPhase("-")
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private func selectQuality(_ quality: Int, viewModel: VideoDetailViewModel) async {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let variant = viewModel.playVariants.first(where: {
                $0.quality == quality && $0.isPlayable
            }) {
                viewModel.selectPlayVariant(variant)
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func waitForViewModel(timeout: TimeInterval) async -> VideoDetailViewModel? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let viewModel = VideoDetailPlaybackLocator.currentViewModel {
                return viewModel
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private func waitForPlayback(_ viewModel: VideoDetailViewModel, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if viewModel.stablePlayerViewModel?.hasPresentedPlayback == true {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func mark(_ name: String) {
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: "hitchSelfTest",
            message: "selfTestPhase=\(name)"
        )
    }
}

/// 程序化滚动主滚动视图，模拟用户上下翻阅详情页。
@MainActor
private enum DetailScrollDriver {
    static func scroll(duration: TimeInterval) async {
        guard let scrollView = mainScrollView() else { return }
        let end = Date().addingTimeInterval(duration)
        var offset = scrollView.contentOffset.y
        var direction: CGFloat = 1
        while Date() < end {
            let lowerBound = -scrollView.adjustedContentInset.top
            let upperBound = max(
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom,
                lowerBound
            )
            if offset >= upperBound - 20 { direction = -1 }
            if offset <= lowerBound + 20 { direction = 1 }
            offset = min(max(offset + direction * 300, lowerBound), upperBound)
            UIView.animate(withDuration: 0.30, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: false)
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
        }
    }

    private static func mainScrollView() -> UIScrollView? {
        var candidates: [UIScrollView] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                collectScrollViews(in: window, into: &candidates)
            }
        }
        return candidates
            .filter { scrollView in
                scrollView.window != nil
                    && scrollView.bounds.height > 200
                    && scrollView.contentSize.height > scrollView.bounds.height * 1.2
            }
            .max { lhs, rhs in
                lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
            }
    }

    private static func collectScrollViews(in view: UIView, into candidates: inout [UIScrollView]) {
        if let scrollView = view as? UIScrollView {
            candidates.append(scrollView)
        }
        for subview in view.subviews {
            collectScrollViews(in: subview, into: &candidates)
        }
    }
}

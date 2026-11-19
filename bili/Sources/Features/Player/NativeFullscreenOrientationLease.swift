import UIKit

/// 原生播放器控件实验的系统全屏方向租约（借鉴 ibili `PlayerFullscreenOrientationPolicy` 的
/// 单播放页简化版）。AVKit 系统全屏按钮触发全屏展示，租约只在转场期间持有方向掩码：
/// - 进入期：按视频内容方向锁定目标（横屏视频 → `landscapeRight`，竖屏视频 → `portrait`）；
/// - 全屏期：放开为自由旋转；
/// - 退出期：回正到进入前方向，转场结束后补发方向请求并重试，到位后释放并恢复自由旋转。
@MainActor
final class NativeFullscreenOrientationLease {
    static let shared = NativeFullscreenOrientationLease()

    enum Phase: Equatable {
        case entering(target: UIInterfaceOrientation)
        case fullscreen
        case restoring(target: UIInterfaceOrientation)
    }

    private(set) var phase: Phase?
    private var entryOrientation: UIInterfaceOrientation = .portrait
    private var entryTargetOrientation: UIInterfaceOrientation = .landscapeRight
    private weak var scene: UIWindowScene?
    private weak var orientationController: UIViewController?
    private var geometryObservation: NSKeyValueObservation?
    private var pendingRequestMask: UIInterfaceOrientationMask?
    private var retryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    /// 租约正常释放（全屏退出回正到位）后的回调；`cancel()` 静默取消时不调用。
    var onRelease: (@MainActor () -> Void)?

    func beginEntry(
        target: UIInterfaceOrientation,
        entry: UIInterfaceOrientation,
        scene: UIWindowScene?,
        orientationController: UIViewController? = nil
    ) {
        cancel()
        entryOrientation = entry
        entryTargetOrientation = target
        self.scene = scene
        self.orientationController = orientationController
        phase = .entering(target: target)
        print("[NativeFullscreen] lease beginEntry target=\(target) entry=\(entry) scene=\(scene != nil)")
        observeGeometry()
        orientationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        apply(target: target)
        scheduleTimeout()
    }

    func beginFullscreenRotation() {
        guard phase != nil else { return }
        cancelTasks()
        let desiredTarget = entryTargetOrientation
        let currentOrientation = scene?.effectiveGeometry.interfaceOrientation
        phase = .fullscreen
        pendingRequestMask = nil
        print("[NativeFullscreen] lease beginFullscreenRotation current=\(String(describing: currentOrientation)) desired=\(desiredTarget)")
        AppOrientationLock.update(to: .allButUpsideDown, in: scene)
        orientationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if currentOrientation != desiredTarget,
           let mask = Self.mask(for: desiredTarget) {
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }

    func beginRestore() {
        guard phase != nil else { return }
        let fullscreenOrientation = scene?.effectiveGeometry.interfaceOrientation
        let target = Self.exitOrientation(
            entry: entryOrientation,
            fullscreen: fullscreenOrientation
        )
        phase = .restoring(target: target)
        print("[NativeFullscreen] lease beginRestore fullscreen=\(String(describing: fullscreenOrientation)) target=\(target)")
        apply(target: target)
        scheduleTimeout()
    }

    /// AVKit 收起转场期间提交的方向请求可能不生效，转场结束后再补一次并继续重试。
    func finishRestoreIfNeeded() {
        guard case .restoring(let target) = phase else { return }
        let current = scene?.effectiveGeometry.interfaceOrientation
        print("[NativeFullscreen] lease finishRestoreIfNeeded current=\(String(describing: current)) target=\(target)")
        if current == target {
            release()
            return
        }
        apply(target: target)
        scheduleRetry()
    }

    /// 详情页离开导航层级等场景下静默取消，不触发 `onRelease`，方向由调用方接管。
    func cancel() {
        if phase != nil {
            print("[NativeFullscreen] lease cancel phase=\(String(describing: phase))")
        }
        cancelTasks()
        geometryObservation?.invalidate()
        geometryObservation = nil
        pendingRequestMask = nil
        scene = nil
        orientationController = nil
        phase = nil
    }

    private func release() {
        print("[NativeFullscreen] lease release")
        cancel()
        onRelease?()
        onRelease = nil
    }

    private func apply(target: UIInterfaceOrientation) {
        guard let mask = Self.mask(for: target) else { return }
        guard pendingRequestMask != mask else { return }
        print("[NativeFullscreen] lease apply mask=\(mask.rawValue)")
        pendingRequestMask = mask
        AppOrientationLock.update(to: mask, in: scene)
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pendingRequestMask == mask else { return }
                self.pendingRequestMask = nil
            }
        }
    }

    private func handleGeometryChange() {
        switch phase {
        case .entering(let target), .restoring(let target):
            if scene?.effectiveGeometry.interfaceOrientation == target {
                if case .restoring = phase {
                    release()
                }
                return
            }
            apply(target: target)
        case .fullscreen, nil:
            break
        }
    }

    private func observeGeometry() {
        guard geometryObservation == nil, let scene else { return }
        geometryObservation = scene.observe(
            \.effectiveGeometry,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleGeometryChange()
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, !Task.isCancelled else { return }
            self.finishRestoreIfNeeded()
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.release()
        }
    }

    private func cancelTasks() {
        retryTask?.cancel()
        retryTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// 全屏目标方向：横屏视频进横屏，竖屏视频保持竖屏；未知尺寸按横屏处理。
    static func fullscreenTargetOrientation(presentationSize: CGSize) -> UIInterfaceOrientation {
        let width = abs(presentationSize.width)
        let height = abs(presentationSize.height)
        guard width > 0, height > 0, width.isFinite, height.isFinite else {
            return .landscapeRight
        }
        return width > height ? .landscapeRight : .portrait
    }

    static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    /// 退出方向：竖屏进入回竖屏；横屏进入则回到全屏时所在（或进入时）的横屏方向。
    static func exitOrientation(
        entry: UIInterfaceOrientation,
        fullscreen: UIInterfaceOrientation?
    ) -> UIInterfaceOrientation {
        if entry.isPortrait {
            return .portrait
        }
        if entry.isLandscape,
           let fullscreen,
           fullscreen != .unknown,
           fullscreen != .portraitUpsideDown {
            return fullscreen
        }
        return entry.isLandscape ? entry : .portrait
    }
}

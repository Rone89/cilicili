import UIKit

@MainActor
enum AppOrientationLock {
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func update(
        to orientations: UIInterfaceOrientationMask,
        in scene: UIWindowScene?,
        requestsGeometryUpdate: Bool = false
    ) {
        let didChange = supportedOrientations != orientations
        supportedOrientations = orientations

        let targetScenes = scenes(matching: scene)
        guard didChange || requestsGeometryUpdate else { return }
        requestInterfaceUpdates(in: targetScenes)

        guard requestsGeometryUpdate else { return }
        requestGeometryUpdate(to: orientations, in: targetScenes)
    }

    static func restorePortrait(in scene: UIWindowScene? = nil) {
        let targetScenes = scenes(matching: scene)
        let needsGeometryUpdate = targetScenes.contains {
            !$0.effectiveGeometry.interfaceOrientation.isPortrait
        }
        guard supportedOrientations != .portrait || needsGeometryUpdate else { return }
        supportedOrientations = .portrait
        requestInterfaceUpdates(in: targetScenes)
        guard needsGeometryUpdate else { return }
        requestGeometryUpdate(to: .portrait, in: targetScenes)
    }

    static func requestGeometryUpdate(
        to orientations: UIInterfaceOrientationMask,
        in scene: UIWindowScene?,
        onError: (@MainActor (Error) -> Void)? = nil
    ) {
        requestGeometryUpdate(to: orientations, in: scenes(matching: scene), onError: onError)
    }

    private static func scenes(matching scene: UIWindowScene?) -> [UIWindowScene] {
        if let scene {
            return [scene]
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    private static func requestInterfaceUpdates(in scenes: [UIWindowScene]) {
        scenes
            .flatMap(\.windows)
            .filter(\.participatesInAppOrientationChrome)
            .compactMap(\.rootViewController)
            .forEach { controller in
                var cursor: UIViewController? = controller
                while let current = cursor {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    current.setNeedsStatusBarAppearanceUpdate()
                    current.setNeedsUpdateOfHomeIndicatorAutoHidden()
                    cursor = current.presentedViewController
                }
            }
    }

    private static func requestGeometryUpdate(
        to orientations: UIInterfaceOrientationMask,
        in scenes: [UIWindowScene],
        onError: (@MainActor (Error) -> Void)? = nil
    ) {
        scenes.forEach { scene in
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
            ) { error in
                guard let onError else { return }
                Task { @MainActor in
                    onError(error)
                }
            }
        }
    }
}

private extension UIWindow {
    var participatesInAppOrientationChrome: Bool {
        !isHidden
            && alpha > 0
            && !(self is PlayerHostWindow)
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var hasRegisteredSceneLifecycleObservers = false

    isolated deinit {
        if hasRegisteredSceneLifecycleObservers {
            NotificationCenter.default.removeObserver(self)
        }
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UIWindow.appearance().backgroundColor = LaunchAppearance.backgroundColor
        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PlayerSystemMediaControls.clear()
        LaunchAppearance.applyToConnectedWindows()
        registerEarlySceneBackgroundLifecycleObservers()
        return true
    }

    private func registerEarlySceneBackgroundLifecycleObservers() {
        guard !hasRegisteredSceneLifecycleObservers else { return }
        hasRegisteredSceneLifecycleObservers = true
        let center = NotificationCenter.default
        // Register at launch before any AVPlayerViewController exists so our FIFO
        // handler disconnects visual sinks before AVKit tears down foreground rendering.
        center.addObserver(
            self,
            selector: #selector(handleSceneDidEnterBackgroundNotification(_:)),
            name: UIScene.didEnterBackgroundNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSceneWillEnterForegroundNotification(_:)),
            name: UIScene.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc
    private func handleSceneDidEnterBackgroundNotification(_ notification: Notification) {
        _ = handleSceneDidEnterBackground(notification)
    }

    @objc
    private func handleSceneWillEnterForegroundNotification(_ notification: Notification) {
        handleSceneWillEnterForeground(notification)
    }

    @discardableResult
    func handleSceneDidEnterBackground(_ notification: Notification) -> Bool {
        let application = UIApplication.shared
        let context = Self.makeSceneLifecycleEvaluationContext(
            for: notification,
            activePlayerWindowScene: ActivePlaybackCoordinator.shared.activePlayerWindowScene,
            connectedScenes: application.connectedScenes,
            applicationState: application.applicationState
        )
        guard Self.shouldPauseActivePlaybackForSceneDidEnterBackground(context) else {
            let role = (notification.object as? UIWindowScene)?.session.role.rawValue ?? "none"
            PlayerMetricsLog.diagnostic(
                "appLifecycle ignoreSceneBackground role=\(role) matchingPlayer=\(context.matchesActivePlayerWindowScene) hasActiveScene=\(context.hasActivePlayerWindowScene) otherFG=\(context.hasOtherForegroundApplicationScene) appState=\(context.applicationState.rawValue)"
            )
            return false
        }
        return ActivePlaybackCoordinator.shared.pauseActivePlaybackForAppBackground()
    }

    func handleSceneWillEnterForeground(_ notification: Notification) {
        let application = UIApplication.shared
        let context = Self.makeSceneLifecycleEvaluationContext(
            for: notification,
            activePlayerWindowScene: ActivePlaybackCoordinator.shared.activePlayerWindowScene,
            connectedScenes: application.connectedScenes,
            applicationState: application.applicationState
        )
        guard Self.shouldRestoreActivePlaybackForSceneWillEnterForeground(context) else { return }
        ActivePlaybackCoordinator.shared.restoreActivePlaybackForAppForeground()
    }

    struct SceneLifecycleEvaluationContext {
        let hasNotificationObject: Bool
        let isWindowScene: Bool
        let isApplicationWindowScene: Bool
        let hasPrimaryAppWindow: Bool
        let matchesActivePlayerWindowScene: Bool
        let hasActivePlayerWindowScene: Bool
        let hasOtherForegroundApplicationScene: Bool
        let applicationState: UIApplication.State
    }

    static func makeSceneLifecycleEvaluationContext(
        for notification: Notification,
        activePlayerWindowScene: UIWindowScene?,
        connectedScenes: Set<UIScene>,
        applicationState: UIApplication.State
    ) -> SceneLifecycleEvaluationContext {
        let object = notification.object
        let windowScene = object as? UIWindowScene
        let isApplicationWindowScene = windowScene?.session.role == .windowApplication
        let hasPrimaryAppWindow = windowScene?.windows.contains { !($0 is PlayerHostWindow) } ?? false
        let matchesActivePlayerWindowScene = if let windowScene, let activePlayerWindowScene {
            windowScene === activePlayerWindowScene
        } else {
            false
        }
        let hasOtherForegroundApplicationScene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { candidate in
                candidate !== windowScene
                    && candidate.session.role == .windowApplication
                    && (candidate.activationState == .foregroundActive || candidate.activationState == .foregroundInactive)
                    && candidate.windows.contains { !($0 is PlayerHostWindow) }
            }
        return SceneLifecycleEvaluationContext(
            hasNotificationObject: object != nil,
            isWindowScene: windowScene != nil,
            isApplicationWindowScene: isApplicationWindowScene,
            hasPrimaryAppWindow: hasPrimaryAppWindow,
            matchesActivePlayerWindowScene: matchesActivePlayerWindowScene,
            hasActivePlayerWindowScene: activePlayerWindowScene != nil,
            hasOtherForegroundApplicationScene: hasOtherForegroundApplicationScene,
            applicationState: applicationState
        )
    }

    static func shouldPauseActivePlaybackForSceneDidEnterBackground(
        _ context: SceneLifecycleEvaluationContext
    ) -> Bool {
        guard context.hasNotificationObject else {
            return context.applicationState != .active && !context.hasOtherForegroundApplicationScene
        }
        guard context.isWindowScene, context.isApplicationWindowScene else {
            return false
        }
        if context.hasActivePlayerWindowScene {
            return context.matchesActivePlayerWindowScene
        }
        return context.hasPrimaryAppWindow && !context.hasOtherForegroundApplicationScene
    }

    static func shouldRestoreActivePlaybackForSceneWillEnterForeground(
        _ context: SceneLifecycleEvaluationContext
    ) -> Bool {
        guard context.hasNotificationObject else { return true }
        guard context.isWindowScene, context.isApplicationWindowScene else {
            return false
        }
        if context.hasActivePlayerWindowScene {
            return context.matchesActivePlayerWindowScene
        }
        return context.hasPrimaryAppWindow
    }

    func applicationWillTerminate(_ application: UIApplication) {
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        PlayerSystemMediaControls.clear()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("[AppLifecycle] applicationDidEnterBackground")
        ActivePlaybackCoordinator.shared.pauseActivePlaybackForAppBackground()
    }

    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        print("[AppLifecycle] protectedDataWillBecomeUnavailable")
        ActivePlaybackCoordinator.shared.pauseActivePlaybackForAppBackground()
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppOrientationLock.supportedOrientations
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        RemoteImageDisplayMemoryCache.shared.clear()
        BiliEmoteMemoryCache.clear()
        Task {
            await RemoteImageCache.shared.clearMemoryCache(cancelInFlight: true)
            await PlayURLCache.shared.clearMemoryCache()
            await DanmakuResourceCache.shared.clear()
        }
    }
}

@MainActor
enum LaunchAppearance {
    static let backgroundColor = UIColor(named: "CiliciliDynamicLaunchBackground") ?? UIColor { traitCollection in
        UIColor.systemBackground.resolvedColor(with: traitCollection)
    }

    static func apply(to window: UIWindow?) {
        guard let window else { return }
        window.backgroundColor = backgroundColor
    }

    static func applyToConnectedWindows() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach(apply(to:))
    }
}

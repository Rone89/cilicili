import UIKit

@MainActor
enum AppOrientationLock {
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func update(
        to orientations: UIInterfaceOrientationMask,
        in scene: UIWindowScene?,
        requestsGeometryUpdate: Bool = false
    ) {
        supportedOrientations = orientations

        let targetScenes = scenes(matching: scene)
        requestInterfaceUpdates(in: targetScenes)

        guard requestsGeometryUpdate else { return }
        requestGeometryUpdate(to: orientations, in: targetScenes)
    }

    static func restorePortrait(in scene: UIWindowScene? = nil) {
        update(to: .portrait, in: scene, requestsGeometryUpdate: true)
    }

    static func requestGeometryUpdate(
        to orientations: UIInterfaceOrientationMask,
        in scene: UIWindowScene?
    ) {
        requestGeometryUpdate(to: orientations, in: scenes(matching: scene))
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
                controller.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller.setNeedsStatusBarAppearanceUpdate()
                controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
    }

    private static func requestGeometryUpdate(
        to orientations: UIInterfaceOrientationMask,
        in scenes: [UIWindowScene]
    ) {
        scenes.forEach { scene in
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
            ) { _ in }
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
        LaunchAppearance.applyToConnectedWindows()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppOrientationLock.supportedOrientations
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Task {
            await RemoteImageCache.shared.clearMemoryCache(cancelInFlight: true)
            await PlayURLCache.shared.clearMemoryCache()
            await SubtitleDanmakuResourceCache.shared.clear()
        }
    }
}

@MainActor
enum LaunchAppearance {
    static let backgroundColor = UIColor(named: "CiliciliDynamicLaunchBackground") ?? UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.047, green: 0.051, blue: 0.055, alpha: 1)
            : UIColor(red: 0.965, green: 0.973, blue: 0.984, alpha: 1)
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

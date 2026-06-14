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

        let targetScenes: [UIWindowScene]
        if let scene {
            targetScenes = [scene]
        } else {
            targetScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        }

        targetScenes
            .flatMap(\.windows)
            .compactMap(\.rootViewController)
            .forEach { controller in
                controller.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller.setNeedsStatusBarAppearanceUpdate()
                controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }

        guard requestsGeometryUpdate else { return }
        targetScenes.forEach { scene in
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
            ) { _ in }
        }
    }

    static func restorePortrait(in scene: UIWindowScene? = nil) {
        update(to: .portrait, in: scene)
        let scenes = scene.map { [$0] } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        scenes.forEach { scene in
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
            ) { _ in }
        }
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
    static let backgroundColor = UIColor(red: 0.965, green: 0.973, blue: 0.984, alpha: 1)

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

import UIKit

@MainActor
enum AppOrientationLock {
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func update(to orientations: UIInterfaceOrientationMask, in scene: UIWindowScene?) {
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
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationLock.supportedOrientations
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Task {
            await RemoteImageCache.shared.clearMemoryCache(cancelInFlight: true)
        }
    }
}

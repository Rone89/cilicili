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
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationLock.supportedOrientations
    }
}

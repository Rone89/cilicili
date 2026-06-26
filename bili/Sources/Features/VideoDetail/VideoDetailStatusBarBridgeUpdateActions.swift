import UIKit

extension StatusBarStyleBridge.Controller {
    func requestChromeUpdate() {
        var controllers = [UIViewController]()
        var current: UIViewController? = self
        while let controller = current {
            controllers.append(controller)
            current = controller.parent
        }
        if let navigationController {
            controllers.append(navigationController)
        }
        if let tabBarController {
            controllers.append(tabBarController)
        }
        if let root = view.window?.rootViewController {
            controllers.append(root)
        }

        controllers.forEach { controller in
            controller.setNeedsStatusBarAppearanceUpdate()
            controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }
}

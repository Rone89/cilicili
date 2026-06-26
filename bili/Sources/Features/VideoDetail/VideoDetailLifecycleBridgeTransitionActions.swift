import UIKit

extension VideoDetailLifecycleBridge.Controller {
    func isClosingNavigationTransition(_ coordinator: UIViewControllerTransitionCoordinator) -> Bool {
        let fromViewController = coordinator.viewController(forKey: .from)
        let toViewController = coordinator.viewController(forKey: .to)
        let navController = fromViewController?.navigationController ?? navigationController

        if fromViewController?.isMovingFromParent == true
            || fromViewController?.isBeingDismissed == true
            || navController?.isBeingDismissed == true {
            return true
        }

        guard let fromViewController,
              let toViewController,
              let navController,
              let toIndex = navController.viewControllers.firstIndex(where: { $0 === toViewController })
        else { return false }

        guard let fromIndex = navController.viewControllers.firstIndex(where: { $0 === fromViewController }) else {
            return true
        }
        return toIndex < fromIndex
    }
}

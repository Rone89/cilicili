import UIKit

extension UIApplication {
    var videoDetailKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isVideoDetailPrimaryKeyWindow }
    }

    var biliForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isVideoDetailPrimaryKeyWindow }
    }
}

private extension UIWindow {
    var isVideoDetailPrimaryKeyWindow: Bool {
        isKeyWindow
            && !isHidden
            && alpha > 0
            && !(self is PlayerHostWindow)
    }
}

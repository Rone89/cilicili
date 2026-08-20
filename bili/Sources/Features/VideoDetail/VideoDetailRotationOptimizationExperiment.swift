import UIKit

nonisolated enum VideoDetailRotationOptimizationExperiment {
    static let storageKey = "cc.bili.videoDetail.rotationOptimizationExperimentEnabled.v1"
    static let defaultIsEnabled = false
}

nonisolated struct VideoDetailRotationOptimizationPolicy: Equatable {
    let isEnabled: Bool

    func hidesContentHost(duringTransitionToLandscape toLandscape: Bool) -> Bool {
        isEnabled || toLandscape
    }

    var publishesContentLayoutDuringSystemTransition: Bool {
        !isEnabled
    }

    func restoresPortraitAfterResolvingPortraitVideo(isCurrentlyLandscape: Bool) -> Bool {
        isEnabled && isCurrentlyLandscape
    }

    func preferredLandscapeInterfaceOrientation(
        currentInterfaceOrientation: UIInterfaceOrientation?,
        deviceOrientation: UIDeviceOrientation
    ) -> UIInterfaceOrientationMask {
        guard isEnabled else { return .landscapeRight }

        if currentInterfaceOrientation == .landscapeLeft {
            return .landscapeLeft
        }
        if currentInterfaceOrientation == .landscapeRight {
            return .landscapeRight
        }

        switch deviceOrientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .landscapeRight
        }
    }
}

import CoreGraphics

enum PlayerSurfaceVerticalAdjustmentTarget: Equatable {
    case brightness
    case volume

    var accessibilityLabel: String {
        switch self {
        case .brightness:
            "屏幕亮度"
        case .volume:
            "音量"
        }
    }
}

nonisolated enum PlayerSurfaceGestureAxis: Equatable {
    case horizontal
    case vertical
}

nonisolated enum PlayerSurfaceGestureAxisPolicy {
    static func axis(
        translation: CGSize,
        activationDistance: CGFloat,
        dominanceRatio: CGFloat
    ) -> PlayerSurfaceGestureAxis? {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        if horizontalDistance >= activationDistance,
           horizontalDistance > verticalDistance * dominanceRatio {
            return .horizontal
        }
        if verticalDistance >= activationDistance,
           verticalDistance > horizontalDistance * dominanceRatio {
            return .vertical
        }
        return nil
    }
}

nonisolated enum PlayerSurfaceVerticalZoneAction: Equatable {
    case brightness
    case volume
    case fullscreenToggle

    var adjustmentTarget: PlayerSurfaceVerticalAdjustmentTarget? {
        switch self {
        case .brightness:
            return .brightness
        case .volume:
            return .volume
        case .fullscreenToggle:
            return nil
        }
    }
}

nonisolated enum PlayerSurfaceFullscreenSwipeDirection: Equatable {
    case enterFullscreen
    case exitFullscreen
}

nonisolated enum PlayerSurfaceVerticalAdjustmentPolicy {
    static func target(startLocationX: CGFloat, width: CGFloat) -> PlayerSurfaceVerticalAdjustmentTarget? {
        guard width > 0, startLocationX >= 0, startLocationX <= width else { return nil }
        return startLocationX < width / 2 ? .brightness : .volume
    }

    static func zoneAction(
        startLocationX: CGFloat,
        width: CGFloat,
        threeZoneEnabled: Bool
    ) -> PlayerSurfaceVerticalZoneAction? {
        guard width > 0, startLocationX >= 0, startLocationX <= width else { return nil }
        guard threeZoneEnabled else {
            return startLocationX < width / 2 ? .brightness : .volume
        }
        let thirdWidth = width / 3
        if startLocationX < thirdWidth {
            return .brightness
        } else if startLocationX < thirdWidth * 2 {
            return .fullscreenToggle
        } else {
            return .volume
        }
    }

    static func fullscreenSwipeDirection(
        verticalTranslation: CGFloat,
        isFullscreenActive: Bool,
        threshold: CGFloat = 36
    ) -> PlayerSurfaceFullscreenSwipeDirection? {
        if !isFullscreenActive && verticalTranslation <= -threshold {
            return .enterFullscreen
        }
        if isFullscreenActive && verticalTranslation >= threshold {
            return .exitFullscreen
        }
        return nil
    }

    static func shouldBegin(
        translation: CGSize,
        activationDistance: CGFloat,
        dominanceRatio: CGFloat
    ) -> Bool {
        PlayerSurfaceGestureAxisPolicy.axis(
            translation: translation,
            activationDistance: activationDistance,
            dominanceRatio: dominanceRatio
        ) == .vertical
    }

    static func adjustedValue(
        initialValue: Float,
        verticalTranslation: CGFloat,
        height: CGFloat
    ) -> Float {
        let clampedInitialValue = min(max(initialValue, 0), 1)
        guard height > 0 else { return clampedInitialValue }
        let adjustment = -Float(verticalTranslation / height)
        return min(max(clampedInitialValue + adjustment, 0), 1)
    }

    static func shouldPresentHardwareVolumeIndicator(
        previousValue: Float,
        currentValue: Float,
        isVerticalAdjusting: Bool
    ) -> Bool {
        guard !isVerticalAdjusting else { return false }
        return abs(currentValue - previousValue) > 0.0001
    }
}

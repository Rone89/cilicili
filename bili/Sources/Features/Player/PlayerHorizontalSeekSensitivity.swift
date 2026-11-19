import Foundation

import CoreGraphics
import Foundation

enum PlayerHorizontalSeekSensitivity {
    private static let piliPlusDefaultSecondsPerFullWidth: TimeInterval = 90
    private static let velocityBoostThresholdPointsPerSecond: CGFloat = 75
    private static let velocityBoostSaturationPointsPerSecond: CGFloat = 650

    static func secondsPerFullWidth(duration _: TimeInterval?) -> TimeInterval {
        piliPlusDefaultSecondsPerFullWidth
    }

    static func effectiveSecondsPerFullWidth(
        duration: TimeInterval?,
        horizontalVelocity: CGFloat
    ) -> TimeInterval {
        let baseSeconds = secondsPerFullWidth(duration: duration)
        let speed = abs(horizontalVelocity)
        guard speed > velocityBoostThresholdPointsPerSecond else {
            return baseSeconds
        }
        let normalized = min(
            max(
                (speed - velocityBoostThresholdPointsPerSecond)
                    / (velocityBoostSaturationPointsPerSecond - velocityBoostThresholdPointsPerSecond),
                0
            ),
            1
        )
        let maxFastSeconds: TimeInterval
        if let duration, duration > 0 {
            let targetSpan = max(360, duration * 0.85)
            maxFastSeconds = min(max(baseSeconds, min(targetSpan, 1_500)), duration)
        } else {
            maxFastSeconds = 360
        }
        guard maxFastSeconds > baseSeconds else { return baseSeconds }
        // Responsive progressive ramp: slow micro-drags stay precise at 90s/width,
        // normal thumb slides cover minutes smoothly, and brisk flicks span most of the video.
        let eased = Double(pow(normalized, 0.82))
        return baseSeconds + (maxFastSeconds - baseSeconds) * eased
    }
}

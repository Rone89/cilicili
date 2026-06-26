import SwiftUI

struct PlayerNativeControlMetrics: Equatable {
    let controlHeight: CGFloat
    let progressControlHeight: CGFloat
    let sliderVisualScale: CGFloat
    let iconSize: CGFloat
    let timeFont: Font
    let stackSpacing: CGFloat
    let groupSpacing: CGFloat
    let controlSpacing: CGFloat
    let sliderHorizontalPadding: CGFloat
    let timeLabelWidth: CGFloat
    let qualityButtonMaxWidth: CGFloat
    let qualityHorizontalPadding: CGFloat

    static let portrait = PlayerNativeControlMetrics(
        controlHeight: 28,
        progressControlHeight: 22,
        sliderVisualScale: 0.82,
        iconSize: 12,
        timeFont: .caption2.monospacedDigit(),
        stackSpacing: 5,
        groupSpacing: 5,
        controlSpacing: 4,
        sliderHorizontalPadding: 8,
        timeLabelWidth: 62,
        qualityButtonMaxWidth: 68,
        qualityHorizontalPadding: 6
    )

    static let landscape = PlayerNativeControlMetrics(
        controlHeight: 34,
        progressControlHeight: 26,
        sliderVisualScale: 0.92,
        iconSize: 14,
        timeFont: .caption.monospacedDigit(),
        stackSpacing: 7,
        groupSpacing: 7,
        controlSpacing: 6,
        sliderHorizontalPadding: 11,
        timeLabelWidth: 86,
        qualityButtonMaxWidth: 92,
        qualityHorizontalPadding: 9
    )
}

private struct PlayerNativeControlMetricsKey: EnvironmentKey {
    static let defaultValue = PlayerNativeControlMetrics.portrait
}

extension EnvironmentValues {
    var playerNativeControlMetrics: PlayerNativeControlMetrics {
        get { self[PlayerNativeControlMetricsKey.self] }
        set { self[PlayerNativeControlMetricsKey.self] = newValue }
    }
}

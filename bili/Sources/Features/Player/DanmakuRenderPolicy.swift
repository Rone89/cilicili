import UIKit

/// Renderer-independent rules; the existing DanmakuKit path keeps its values.
enum DanmakuRenderPolicy {
    static func supports(_ item: DanmakuItem, settings: DanmakuSettings) -> Bool {
        guard item.isSupported,
              !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if item.isScrolling { return settings.danmakuKit.enablesFloating }
        if item.isTopAnchored { return settings.danmakuKit.enablesTop }
        return settings.danmakuKit.enablesBottom
    }

    static func duration(for item: DanmakuItem, viewportWidth: CGFloat) -> TimeInterval {
        item.isScrolling ? (viewportWidth > 640 ? 8.4 : 7.2) : 4.2
    }

    /// 滚动弹幕固定速度（pt/秒）：时长 =（画布宽 + 位图宽）/ 速度。
    /// 速度取横屏既有校准（(852+187)/8.4 ≈ 124），竖屏画布窄则时长自然缩短，
    /// 观感速度两个方向一致；弹幕位图随文本长度变化，飞行距离同步伸缩。
    static func scrollDuration(viewportWidth: CGFloat, bitmapWidth: CGFloat) -> TimeInterval {
        let canvasWidth = max(viewportWidth, 1)
        let width = max(bitmapWidth, 1)
        return Double((canvasWidth + width) / 124)
    }

    static func font(for item: DanmakuItem, viewportWidth: CGFloat, scale: Double,
                     weight: DanmakuFontWeightOption) -> UIFont {
        let compact: CGFloat = viewportWidth > 640 ? 0.86 : 0.70
        let maximum: CGFloat = viewportWidth > 640 ? 24 : 18
        let minimum: CGFloat = viewportWidth > 640 ? 15 : 13
        let pointSize = min(max(CGFloat(item.fontSize) * compact * CGFloat(scale), minimum * 0.9), maximum * 1.35)
        let uiWeight: UIFont.Weight
        switch weight {
        case .light: uiWeight = .light
        case .regular: uiWeight = .regular
        case .medium: uiWeight = .medium
        case .semibold: uiWeight = .semibold
        case .bold: uiWeight = .bold
        case .heavy: uiWeight = .heavy
        case .black: uiWeight = .black
        }
        return UIFont.systemFont(ofSize: pointSize, weight: uiWeight)
    }

    static func maximumActiveCount(width: CGFloat, settings: DanmakuSettings,
                                   rate: Double, loadShedding: Bool) -> Int {
        let environment = PlaybackEnvironment.current
        let sheddingFactor = loadShedding ? 0.46 : 1.0
        let rateFactor = rate >= 1.75 ? 0.58 : (rate > 1.15 ? 0.72 : 1.0)
        let thermalFactor: Double
        if environment.isThermallyConstrained || environment.isLowPowerModeEnabled {
            thermalFactor = min(settings.loadFactor, 0.50)
        } else if environment.isThermallyElevated {
            thermalFactor = min(settings.loadFactor, 0.66)
        } else if environment.shouldPreferConservativePlayback {
            thermalFactor = min(settings.loadFactor, 0.72)
        } else {
            thermalFactor = settings.loadFactor
        }
        return max(loadShedding ? 5 : 8, Int(Double(width > 640 ? 44 : 24) * thermalFactor * sheddingFactor * rateFactor))
    }
}

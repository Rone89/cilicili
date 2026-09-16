import SwiftUI

private struct VideoDetailStandardHorizontalInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 20
}

private struct VideoDetailActionButtonStyleKey: EnvironmentKey {
    static let defaultValue: VideoDetailActionButtonStyle = .plain
}

extension EnvironmentValues {
    /// App-wide horizontal inset for standard video-detail content.
    var videoDetailStandardHorizontalInset: CGFloat {
        get { self[VideoDetailStandardHorizontalInsetKey.self] }
        set { self[VideoDetailStandardHorizontalInsetKey.self] = newValue }
    }

    var videoDetailActionButtonStyle: VideoDetailActionButtonStyle {
        get { self[VideoDetailActionButtonStyleKey.self] }
        set { self[VideoDetailActionButtonStyleKey.self] = newValue }
    }
}

enum VideoDetailContentPageMetrics {
    static let commentsTopPadding: CGFloat = 4
}

import SwiftUI

struct VideoDetailInfoTitleSkeleton: View {
    var body: some View {
        VideoDetailInfoTitleText(text: "视频标题正在加载", isExpanded: false)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

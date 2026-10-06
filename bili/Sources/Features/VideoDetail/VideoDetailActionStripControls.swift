import SwiftUI

struct VideoDetailActionStripShareButton: View {
    let shareURL: URL?
    let shareSubject: String
    let shareMessage: String
    let onShareTap: () -> Void
    let usesPlainStyle: Bool

    init(
        shareURL: URL?,
        shareSubject: String,
        shareMessage: String,
        onShareTap: @escaping () -> Void,
        usesPlainStyle: Bool = false
    ) {
        self.shareURL = shareURL
        self.shareSubject = shareSubject
        self.shareMessage = shareMessage
        self.onShareTap = onShareTap
        self.usesPlainStyle = usesPlainStyle
    }

    var body: some View {
        if let shareURL {
            ShareLink(
                item: shareURL,
                subject: Text(shareSubject),
                message: Text(shareMessage)
            ) {
                VideoDetailActionStripIconLabel(
                    systemImage: "square.and.arrow.up",
                    foregroundStyle: usesPlainStyle ? .secondary : .primary,
                    side: VideoDetailActionStrip.Metrics.actionLabelSide,
                    iconSize: VideoDetailActionStrip.Metrics.iconSize
                )
            }
            .videoDetailActionStripButtonAppearance(
                usesPlainStyle: usesPlainStyle,
                tint: usesPlainStyle ? .secondary : nil
            )
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { _ in onShareTap() })
            .accessibilityLabel("分享视频")
        } else {
            VideoDetailActionStripIconButton(
                accessibilityTitle: "分享视频",
                systemImage: "square.and.arrow.up",
                foregroundStyle: .secondary,
                isDisabled: true,
                action: {},
                usesPlainStyle: usesPlainStyle
            )
        }
    }
}

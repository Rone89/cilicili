import SwiftUI

private struct DynamicDetailCommentRowLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var usesDynamicDetailCommentRowLayout: Bool {
        get { self[DynamicDetailCommentRowLayoutKey.self] }
        set { self[DynamicDetailCommentRowLayoutKey.self] = newValue }
    }
}

struct CommentRowLayout<Avatar: View, Header: View, BodyContent: View, Media: View, Reply: View>: View {
    let avatar: Avatar
    let header: Header
    let bodyContent: BodyContent
    let media: Media
    let reply: Reply
    let contentSpacing: CGFloat
    let verticalPadding: CGFloat

    init(
        contentSpacing: CGFloat = 5,
        verticalPadding: CGFloat = 8,
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder header: () -> Header,
        @ViewBuilder bodyContent: () -> BodyContent,
        @ViewBuilder media: () -> Media,
        @ViewBuilder reply: () -> Reply
    ) {
        self.avatar = avatar()
        self.header = header()
        self.bodyContent = bodyContent()
        self.media = media()
        self.reply = reply()
        self.contentSpacing = contentSpacing
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: contentSpacing) {
                header
                bodyContent
                media
                reply
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, verticalPadding)
    }
}

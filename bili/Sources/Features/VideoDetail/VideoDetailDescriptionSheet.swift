import Foundation
import SwiftUI
import UIKit

struct VideoDescriptionSheet: View {
    @ObservedObject var store: VideoDetailDescriptionRenderStore
    let toggleFollow: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VideoTitleText(text: store.titleText.normalizedDetailTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VideoDescriptionOwnerRow(
                        owner: store.owner,
                        fanCountText: store.fanCountText,
                        isFollowing: store.isFollowing,
                        isMutatingInteraction: store.isMutatingInteraction
                    ) {
                        Task { await toggleFollow() }
                    }

                    Label(store.publishDateText, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    BiliLinkedText(
                        store.descriptionText,
                        font: UIFont.preferredFont(forTextStyle: .body),
                        textColor: .primary
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .navigationTitle("视频简介")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct VideoTitleText: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .left
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context _: Context) {
        label.text = text
        label.font = Self.font
        label.textColor = .label
        label.lineBreakMode = .byWordWrapping
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context _: Context) -> CGSize? {
        guard let width = proposal.width ?? (label.bounds.width > 1 ? label.bounds.width : nil),
              width > 1
        else {
            return nil
        }
        label.preferredMaxLayoutWidth = width
        return label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static var font: UIFont {
        let baseFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
        return UIFontMetrics(forTextStyle: .title3).scaledFont(for: baseFont)
    }
}

private struct VideoDescriptionOwnerRow: View {
    let owner: VideoOwner?
    let fanCountText: String
    let isFollowing: Bool
    let isMutatingInteraction: Bool
    let toggleFollow: () -> Void

    var body: some View {
        let canOpenUploader = (owner?.mid ?? 0) > 0

        HStack(spacing: 10) {
            if let owner, canOpenUploader {
                NavigationLink(value: owner) {
                    ownerIdentity(owner: owner, fanCountText: fanCountText, showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                ownerIdentity(owner: owner, fanCountText: fanCountText, showsChevron: false)
            }

            Spacer(minLength: 8)

            Button {
                toggleFollow()
            } label: {
                Text(isFollowing ? "已关注" : "+ 关注")
                    .font(.caption.weight(.bold))
                    .frame(minWidth: 58)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isFollowing ? Color(.tertiarySystemFill) : Color.pink.opacity(0.12))
                    .foregroundStyle(isFollowing ? Color.secondary : Color.pink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenUploader || isMutatingInteraction)
        }
    }

    private func ownerIdentity(owner: VideoOwner?, fanCountText: String, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            AvatarRemoteImage(urlString: owner?.face, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(owner?.name ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(fanCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension String {
    var normalizedDetailTitle: String {
        var text = self
        ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"].forEach {
            text = text.replacingOccurrences(of: $0, with: "")
        }
        ["\u{2028}", "\u{2029}"].forEach {
            text = text.replacingOccurrences(of: $0, with: " ")
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(
            of: #"([\p{Han}\p{Hiragana}\p{Katakana}\p{Bopomofo}\p{N}，。！？、：；（）《》“”‘’【】])\s+([\p{Han}\p{Hiragana}\p{Katakana}\p{Bopomofo}\p{N}，。！？、：；（）《》“”‘’【】])"#,
            with: "$1$2",
            options: .regularExpression
        )
        return text
    }
}

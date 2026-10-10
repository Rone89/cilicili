import SwiftUI

nonisolated enum NativePrivateMessageTimeline {
    struct Entry: Identifiable {
        let message: AccountPrivateMessage
        let showsTimestamp: Bool
        let startsSenderGroup: Bool
        var id: Int { message.id }
    }

    static func entries(_ messages: [AccountPrivateMessage], calendar: Calendar = .current) -> [Entry] {
        messages.enumerated().map { index, message in
            let previous = index > 0 ? messages[index - 1] : nil
            let showsTimestamp: Bool
            if let timestamp = message.timestamp {
                if let previousTimestamp = previous?.timestamp {
                    showsTimestamp = !calendar.isDate(timestamp, inSameDayAs: previousTimestamp)
                        || timestamp.timeIntervalSince(previousTimestamp) >= 300
                } else {
                    showsTimestamp = true
                }
            } else {
                showsTimestamp = false
            }
            return Entry(message: message, showsTimestamp: showsTimestamp,
                         startsSenderGroup: previous?.senderID != message.senderID || showsTimestamp)
        }
    }
}

struct NativePrivateMessageHeader: View {
    let actor: AccountMessageActor

    var body: some View {
        HStack(spacing: 6) {
            avatar
            name
        }
        .frame(maxWidth: 200, minHeight: 44, maxHeight: 44)
        .accessibilityIdentifier("privateMessage.header")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("与\(actor.name)的私信")
    }

    private var avatar: some View {
        AvatarRemoteImage(urlString: actor.avatarURLString, pixelSize: 128) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
        .fixedSize()
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var name: some View {
        Text(actor.name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
    }
}

struct NativePrivateMessageComposer: View {
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    let isSending: Bool
    let isSendingImage: Bool
    let hasEmotes: Bool
    let showPhotos: () -> Void
    let showEmotes: () -> Void
    let send: () -> Void
    @Environment(\.appThemeTintColor) private var tint

    private var isBusy: Bool { isSending || isSendingImage }
    // Match the 48pt visible system toolbar capsule while the keyboard is closed.
    // This is a minimum: multiline text and larger fonts can still grow the field.
    private var baseControlHeight: CGFloat { focus.wrappedValue ? 44 : 48 }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            inputBar
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button("照片", systemImage: "photo", action: showPhotos)
                Button("B站表情", systemImage: "face.smiling", action: showEmotes)
                    .disabled(!hasEmotes)
            } label: {
                Group {
                    if isSendingImage { ProgressView().controlSize(.small) }
                    else { Image(systemName: "plus").font(.title3.weight(.medium)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .frame(width: baseControlHeight, height: baseControlHeight)
            .foregroundStyle(tint)
            .glassEffect(.regular.interactive(), in: Circle())
            .disabled(isBusy)
            .accessibilityLabel("添加附件")
            .accessibilityIdentifier("privateMessage.attachments")

            HStack(alignment: .bottom, spacing: 2) {
                TextField("私信", text: $text, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .appTypography(.messageBody, fallback: .body)
                    .textFieldStyle(.plain)
                    .focused(focus)
                    .submitLabel(.return)
                    .padding(.leading, 14)
                    .padding(.vertical, 11)
                    .frame(minHeight: baseControlHeight)
                    .disabled(isBusy)
                    .accessibilityLabel("私信内容")
                    .accessibilityIdentifier("privateMessage.composer")

                Button(action: send) {
                    Group {
                        if isSending { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                    }
                    .frame(width: 44, height: baseControlHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .disabled(isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送私信")
                .accessibilityIdentifier("privateMessage.send")
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("privateMessage.inputContainer")
        }
    }
}

/// Own focus inside the modal presentation rather than the underlying conversation.
struct NativePrivateMessageComposerPresentation<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: (FocusState<Bool>.Binding) -> Content
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            content($isFocused)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .task { isFocused = true }
    }
}

/// Measure the same attachments, styled runs and line boxes used by BiliEmoteText.
@MainActor
enum PrivateMessageTextLayout {
    static func attributedText(text: String, inlineEmotes: [String: BiliInlineEmote], font: UIFont) -> NSAttributedString {
        BiliEmoteRenderInput(
            content: nil, inlineEmotes: inlineEmotes, plainText: text,
            baseFont: font, textColor: .label, accentColor: .systemBlue,
            leadingName: nil, leadingNameColor: .label, leadingNameFont: nil,
            emoteSize: 21 * font.pointSize / AppTypography.Role.messageBody.pointSize,
            lineLimit: nil, lineSpacing: 0
        ).render().attributedString
    }

    static func width(text: String, inlineEmotes: [String: BiliInlineEmote], font: UIFont, maximumWidth: CGFloat) -> CGFloat {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = attributedText(text: text, inlineEmotes: inlineEmotes, font: font)
        let size = label.sizeThatFits(CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
        return min(max(ceil(size.width), 12), maximumWidth)
    }
}

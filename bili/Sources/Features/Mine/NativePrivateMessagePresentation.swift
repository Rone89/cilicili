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
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .frame(width: 44, height: 44)
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
                    .disabled(isBusy)
                    .accessibilityLabel("私信内容")
                    .accessibilityIdentifier("privateMessage.composer")

                Button(action: send) {
                    Group {
                        if isSending { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .disabled(isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送私信")
                .accessibilityIdentifier("privateMessage.send")
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

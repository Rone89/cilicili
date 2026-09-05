import SwiftUI
import PhotosUI

struct DynamicCommentComposerTarget: Identifiable, Equatable, Sendable {
    let rootID: Int?
    let parentID: Int?
    let authorName: String?

    static let dynamic = DynamicCommentComposerTarget(
        rootID: nil,
        parentID: nil,
        authorName: nil
    )

    static func reply(root: Comment, parent: Comment) -> DynamicCommentComposerTarget {
        DynamicCommentComposerTarget(
            rootID: root.rpid,
            parentID: parent.rpid,
            authorName: parent.member?.uname
        )
    }

    var id: String {
        guard let rootID, let parentID else { return "dynamic" }
        return "reply:\(rootID):\(parentID)"
    }

    var title: String {
        authorName == nil ? "发表评论" : "回复评论"
    }

    var prompt: String {
        guard let authorName, !authorName.isEmpty else { return "友善发言，理性讨论" }
        return "回复 @\(authorName)"
    }
}

struct DynamicCommentComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: String
    let target: DynamicCommentComposerTarget
    let submit: (String) async throws -> Void

    @FocusState private var isEditorFocused: Bool
    @State private var selectedDetent = PresentationDetent.medium
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachedImage: Image?
    @State private var showsUnsupportedImageAlert = false

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let authorName = target.authorName, !authorName.isEmpty {
                    Label("回复 @\(authorName)", systemImage: "arrowshape.turn.up.left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                editor
                .frame(maxHeight: .infinity)

                attachmentPreview
            }
            .padding(16)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24, style: .continuous))
            .padding(12)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { composerToolbar }
        }
        .presentationBackground(.clear)
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            isEditorFocused = true
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data)
                else { return }
                attachedImage = Image(uiImage: uiImage)
                showsUnsupportedImageAlert = true
            }
        }
        .alert("暂不支持图片评论", isPresented: $showsUnsupportedImageAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("当前动态评论接口仅支持文字，图片已保留在输入框中，暂不能发送。")
        }
        .alert("评论发送失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .accessibilityLabel("评论内容")
                .accessibilityIdentifier("dynamic.comment.composer.editor")
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let attachedImage {
            HStack(spacing: 8) {
                attachedImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("已选择图片，当前动态评论接口暂不支持发送图片")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    selectedPhoto = nil
                    self.attachedImage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除图片")
            }
        }
    }

    @ToolbarContentBuilder
    private var composerToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "photo")
                    }
                    .accessibilityIdentifier("dynamic.comment.composer.photo")
                    .accessibilityLabel("添加图片")

                    Button {
                        isEditorFocused = true
                    } label: {
                        Image(systemName: "face.smiling")
                    }
                    .accessibilityLabel("输入表情")
                    .accessibilityHint("使用系统键盘输入表情")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .disabled(isSubmitting)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(action: submitDraft) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text("发送")
                }
            }
            .disabled(normalizedDraft.isEmpty || isSubmitting)
            .accessibilityLabel(isSubmitting ? "正在发送评论" : "发送评论")
            .accessibilityIdentifier("dynamic.comment.composer.send")
        }

    }

    private func submitDraft() {
        let message = normalizedDraft
        guard !message.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            do {
                try await submit(message)
                draft = ""
                isEditorFocused = false
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

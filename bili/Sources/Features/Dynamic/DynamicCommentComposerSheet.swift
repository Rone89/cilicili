import SwiftUI

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

                    if draft.isEmpty {
                        Text(target.prompt)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(16)
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isEditorFocused = false
                        dismiss()
                    }
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

                ToolbarItem(placement: .keyboard) {
                    Button("完成") {
                        isEditorFocused = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            isEditorFocused = true
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

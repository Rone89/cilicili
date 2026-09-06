import SwiftUI
import PhotosUI
import UIKit

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
    @EnvironmentObject private var dependencies: AppDependencies
    @Binding var draft: String
    let target: DynamicCommentComposerTarget
    let api: BiliAPIClient
    let submit: (String, [DynamicCommentImage]?) async throws -> Void

    @FocusState private var isEditorFocused: Bool
    @State private var selectedDetent = PresentationDetent.medium
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var selectedPhotos = [PhotosPickerItem]()
    @State private var attachedImageDatas = [Data]()
    @State private var showsInlinePhotoPicker = false
    @State private var showsFullPhotoPicker = false
    @State private var isUploadingImage = false
    @State private var emotes = [BiliInlineEmote]()
    @State private var showsEmotePicker = false

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesKeyboardAnchoredEmotePicker: Bool {
        dependencies.libraryStore.keyboardAnchoredCommentEmotePickerExperimentEnabled
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
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

                if showsInlinePhotoPicker && !showsEmotePicker {
                    inlinePhotoPicker
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showsEmotePicker && usesKeyboardAnchoredEmotePicker {
                    DynamicInlineCommentEmotePicker(
                        emotes: emotes,
                        onSelect: insertEmote
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
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
            emotes = (try? await api.fetchCommentEmotes()) ?? []
        }
        .onChange(of: selectedPhotos) { _, items in
            Task {
                var imageDatas = [Data]()
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data)
                    else { continue }
                    imageDatas.append(uiImage.jpegData(compressionQuality: 0.9) ?? data)
                }
                attachedImageDatas = imageDatas
                if !imageDatas.isEmpty {
                    dismissInlinePhotoPicker()
                }
            }
        }
        .photosPicker(
            isPresented: $showsFullPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 9,
            matching: .images,
            preferredItemEncoding: .current
        )
        .popover(isPresented: Binding(
            get: { showsEmotePicker && !usesKeyboardAnchoredEmotePicker },
            set: { showsEmotePicker = $0 }
        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            DynamicCommentEmotePicker(emotes: emotes) { token in
                insertEmote(token)
            }
            .presentationCompactAdaptation(.popover)
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
        if !attachedImageDatas.isEmpty {
            HStack(spacing: 8) {
                Text("已选择 \(attachedImageDatas.count) 张图片")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    selectedPhotos = []
                    attachedImageDatas = []
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
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                let shouldShowPhotoPicker = !showsInlinePhotoPicker
                withAnimation(.smooth) {
                    showsInlinePhotoPicker = shouldShowPhotoPicker
                    showsEmotePicker = false
                    isEditorFocused = !shouldShowPhotoPicker
                    if shouldShowPhotoPicker {
                        selectedDetent = .large
                    }
                }
            } label: {
                Image(systemName: "photo")
            }
            .accessibilityIdentifier("dynamic.comment.composer.photo")
            .accessibilityLabel(showsInlinePhotoPicker ? "收起照片选择器" : "添加图片")

            Button {
                if usesKeyboardAnchoredEmotePicker {
                    withAnimation(.smooth) {
                        showsInlinePhotoPicker = false
                        showsEmotePicker = true
                        isEditorFocused = false
                        selectedDetent = .large
                    }
                } else {
                    withAnimation(.smooth) {
                        showsEmotePicker = true
                        isEditorFocused = false
                        selectedDetent = .large
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
            }
            .accessibilityLabel("输入表情")
            .accessibilityHint("使用系统键盘输入表情")
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

    private var inlinePhotoPicker: some View {
        DynamicInlinePhotoPickerPanel(
            selection: $selectedPhotos,
            showsFullPicker: $showsFullPhotoPicker,
            onDismiss: dismissInlinePhotoPicker
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dismissInlinePhotoPicker() {
        withAnimation(.smooth) {
            showsInlinePhotoPicker = false
            selectedDetent = .medium
        }
        isEditorFocused = true
    }

    private func dismissEmotePicker() {
        withAnimation(.smooth) {
            showsEmotePicker = false
            selectedDetent = .medium
        }
        isEditorFocused = true
    }

    private func insertEmote(_ token: String) {
        draft += token
        dismissEmotePicker()
    }

    private func submitDraft() {
        let message = normalizedDraft
        guard !message.isEmpty, !isSubmitting, !isUploadingImage else { return }
        isSubmitting = true
        Task { @MainActor in
            do {
                var pictures: [DynamicCommentImage]?
                if !attachedImageDatas.isEmpty {
                    isUploadingImage = true
                    pictures = []
                    for imageData in attachedImageDatas {
                        pictures?.append(try await api.uploadDynamicCommentImage(imageData))
                    }
                    isUploadingImage = false
                }
                try await submit(message, pictures)
                draft = ""
                isEditorFocused = false
                selectedPhotos = []
                attachedImageDatas = []
                Haptics.success()
                dismiss()
            } catch {
                isUploadingImage = false
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

private struct DynamicCommentEmotePicker: View {
    let emotes: [BiliInlineEmote]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(minimum: 44), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            Group {
                if emotes.isEmpty {
                    ContentUnavailableView("暂无可用表情", systemImage: "face.smiling")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(emotes, id: \.token) { emote in
                                Button {
                                    onSelect(emote.token)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 5) {
                                        CachedRemoteImage(url: emote.displayURL.flatMap(URL.init(string:)), targetPixelSize: 88) { image in
                                            image.resizable().scaledToFit()
                                        } placeholder: {
                                            Image(systemName: "face.smiling").foregroundStyle(.secondary)
                                        }
                                        .frame(width: 38, height: 38)
                                        Text(emote.token)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 62)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("表情")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct DynamicInlineCommentEmotePicker: View {
    let emotes: [BiliInlineEmote]
    var bottomGlassExtension: CGFloat = 0
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 40), spacing: 4), count: 7)

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: bottomGlassExtension > 0 ? 0 : 24,
            bottomTrailingRadius: bottomGlassExtension > 0 ? 0 : 24,
            topTrailingRadius: 24,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if emotes.isEmpty {
                ContentUnavailableView("暂无可用表情", systemImage: "face.smiling")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(emotes, id: \.token) { emote in
                            Button {
                                onSelect(emote.token)
                            } label: {
                                CachedRemoteImage(url: emote.displayURL.flatMap { URL(string: $0) }, targetPixelSize: 96) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "face.smiling")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 36, height: 36)
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emote.token)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(panelShape)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height + bottomGlassExtension
                    )
                    .biliGlassEffect(
                        interactive: true,
                        in: panelShape
                    )
            }
        }
        .accessibilityIdentifier("dynamic.comment.emotePicker")
    }
}

struct DynamicInlinePhotoPickerPanel: View {
    @Binding var selection: [PhotosPickerItem]
    @Binding var showsFullPicker: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            PhotosPicker(
                selection: $selection,
                maxSelectionCount: 9,
                selectionBehavior: .continuous,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Color.clear
            }
            .photosPickerStyle(.inline)
            .photosPickerAccessoryVisibility(.hidden)
            .photosPickerDisabledCapabilities(.selectionActions)

            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .accessibilityLabel("收起照片选择器")

                Spacer()

                Button {
                    showsFullPicker = true
                } label: {
                    Text("全部照片")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("打开全部照片")
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
    }
}

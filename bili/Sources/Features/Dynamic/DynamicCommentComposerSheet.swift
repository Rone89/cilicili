import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
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
    @Binding var draft: String
    let target: DynamicCommentComposerTarget
    let api: BiliAPIClient
    let submit: (String, [DynamicCommentImage]?) async throws -> Void

    @FocusState private var isEditorFocused: Bool
    @State private var selectedDetent = PresentationDetent.medium
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachedImageData: Data?
    @State private var showsPhotoPanel = false
    @State private var showsCamera = false
    @State private var showsFileImporter = false
    @State private var isUploadingImage = false
    @State private var emotes = [BiliInlineEmote]()
    @State private var showsEmotePicker = false

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
            emotes = (try? await api.fetchCommentEmotes()) ?? []
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data)
                else { return }
                attachedImageData = uiImage.jpegData(compressionQuality: 0.9) ?? data
                showsPhotoPanel = false
            }
        }
        .sheet(isPresented: $showsCamera) {
            DynamicCommentCameraPicker { image in
                attachedImageData = image.jpegData(compressionQuality: 0.9)
                showsCamera = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
            attachedImageData = image.jpegData(compressionQuality: 0.9) ?? data
            showsPhotoPanel = false
        }
        .popover(isPresented: $showsEmotePicker, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            DynamicCommentEmotePicker(emotes: emotes) { token in
                draft += token
                isEditorFocused = true
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
        .overlay(alignment: .bottomLeading) {
            photoControls
                .padding(12)
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if attachedImageData != nil {
            HStack(spacing: 8) {
                Text("已选择图片")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    selectedPhoto = nil
                    attachedImageData = nil
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
                showsEmotePicker = true
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

    @Namespace private var photoNamespace

    @ViewBuilder
    private var photoControls: some View {
        GlassEffectContainer(spacing: 8) {
            if showsPhotoPanel {
                VStack(alignment: .leading, spacing: 12) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("照片", systemImage: "photo")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .photosPickerStyle(.compact)
                    .accessibilityLabel("照片")

                    Button {
                        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                        showsCamera = true
                    } label: {
                        Label("相机", systemImage: "camera")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    .accessibilityLabel("相机")

                    Button {
                        showsFileImporter = true
                    } label: {
                        Label("文件", systemImage: "paperclip")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("浏览文件")
                }
                .font(.body)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(minWidth: 180)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28, style: .continuous))
                .glassEffectID("dynamic-comment-photo-panel", in: photoNamespace)
            } else {
                Button {
                    showsPhotoPanel = true
                } label: {
                    Image(systemName: "photo")
                }
                .accessibilityLabel("添加图片")
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("dynamic-comment-photo-panel", in: photoNamespace)
            }
        }
        .animation(.smooth, value: showsPhotoPanel)
    }

    private func submitDraft() {
        let message = normalizedDraft
        guard !message.isEmpty, !isSubmitting, !isUploadingImage else { return }
        isSubmitting = true
        Task { @MainActor in
            do {
                var pictures: [DynamicCommentImage]?
                if let attachedImageData {
                    isUploadingImage = true
                    let image = try await api.uploadDynamicCommentImage(attachedImageData)
                    pictures = [image]
                    isUploadingImage = false
                }
                try await submit(message, pictures)
                draft = ""
                isEditorFocused = false
                selectedPhoto = nil
                attachedImageData = nil
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

private struct DynamicCommentCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

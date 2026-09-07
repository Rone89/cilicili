import PhotosUI
import SwiftUI
import UIKit

enum DynamicCommentComposerState: Equatable {
    case idle
    case composing
    case replying(target: DynamicCommentComposerTarget)
    case sending
    case failed(message: String)
}

struct DynamicKeyboardHeightReader: UIViewRepresentable {
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> DynamicKeyboardHeightProbeView {
        let view = DynamicKeyboardHeightProbeView()
        view.onHeightChange = { height in
            self.height = height
        }
        return view
    }

    func updateUIView(_ uiView: DynamicKeyboardHeightProbeView, context: Context) {
        uiView.onHeightChange = { height in
            self.height = height
        }
    }
}

final class DynamicKeyboardHeightProbeView: UIView {
    var onHeightChange: ((CGFloat) -> Void)?
    private var reportedHeight: CGFloat = -.infinity

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let window else { return }
        let keyboardFrame = convert(keyboardLayoutGuide.layoutFrame, to: window)
        let height = max(0, window.bounds.maxY - keyboardFrame.minY)
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?(height)
        }
    }
}

private enum DynamicDetailComposerPanel: Equatable {
    case emotes
    case photos
}

private struct DynamicComposerTextView: UIViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let usesEmoteInputView: Bool
    let emoteInputHeight: CGFloat
    let emotes: [BiliInlineEmote]
    let onFocusChange: (Bool) -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onFocusChange: onFocusChange,
            onHeightChange: onHeightChange
        )
    }

    func makeUIView(context: Context) -> DynamicComposerUIKitTextView {
        let textView = DynamicComposerUIKitTextView()
        textView.delegate = context.coordinator
        textView.configureEmoteInputView(
            isPresented: usesEmoteInputView,
            height: emoteInputHeight,
            emotes: emotes
        )
        return textView
    }

    func updateUIView(_ textView: DynamicComposerUIKitTextView, context: Context) {
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onHeightChange = onHeightChange
        textView.configureEmoteInputView(
            isPresented: usesEmoteInputView,
            height: emoteInputHeight,
            emotes: emotes
        )

        if textView.text != text {
            textView.text = text
            textView.reportHeightIfNeeded()
        }

        textView.setFocused(isFocused)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var onFocusChange: (Bool) -> Void
        var onHeightChange: (CGFloat) -> Void

        init(
            text: Binding<String>,
            onFocusChange: @escaping (Bool) -> Void,
            onHeightChange: @escaping (CGFloat) -> Void
        ) {
            _text = text
            self.onFocusChange = onFocusChange
            self.onHeightChange = onHeightChange
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            (textView as? DynamicComposerUIKitTextView)?.reportHeightIfNeeded()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            onFocusChange(false)
        }
    }
}

private final class DynamicComposerUIKitTextView: UITextView {
    private var emoteInputView: DynamicComposerEmoteInputView?
    private var currentInputModeIsEmotes = false
    private var reportedHeight: CGFloat = 0
    private var wantsFocus = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        font = .preferredFont(forTextStyle: .body)
        textColor = .label
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textContainer?.lineFragmentPadding = 0
        isScrollEnabled = true
        showsVerticalScrollIndicator = false
        accessibilityLabel = "评论内容"
        accessibilityIdentifier = "dynamic.detail.composer.editor"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportHeightIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setFocused(wantsFocus)
    }

    func setFocused(_ isFocused: Bool) {
        wantsFocus = isFocused
        guard window != nil else { return }
        if isFocused, !isFirstResponder {
            becomeFirstResponder()
        } else if !isFocused, isFirstResponder {
            resignFirstResponder()
        }
    }

    func configureEmoteInputView(
        isPresented: Bool,
        height: CGFloat,
        emotes: [BiliInlineEmote]
    ) {
        let resolvedHeight = max(216, height)
        if isPresented {
            let inputView = emoteInputView ?? DynamicComposerEmoteInputView(
                frame: .zero,
                inputViewStyle: .keyboard
            )
            inputView.configure(
                height: resolvedHeight,
                emotes: emotes,
                insertEmote: { [weak self] token in
                    self?.insertText(token)
                }
            )
            emoteInputView = inputView
            self.inputView = inputView
        } else {
            inputView = nil
        }

        guard currentInputModeIsEmotes != isPresented else { return }
        currentInputModeIsEmotes = isPresented
        if isFirstResponder {
            reloadInputViews()
        }
    }

    func reportHeightIfNeeded() {
        let usableWidth = max(bounds.width, 1)
        let fittingSize = sizeThatFits(CGSize(width: usableWidth, height: .greatestFiniteMagnitude))
        let height = min(max(fittingSize.height, 40), 120)
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            (self.delegate as? DynamicComposerTextView.Coordinator)?.onHeightChange(height)
        }
    }
}

private final class DynamicComposerEmoteInputView: UIInputView {
    private let hostingController = UIHostingController(rootView: AnyView(EmptyView()))
    private var panelHeight: CGFloat = 216

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: panelHeight)
    }

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
        backgroundColor = .clear
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: panelHeight)
    }

    func configure(
        height: CGFloat,
        emotes: [BiliInlineEmote],
        insertEmote: @escaping (String) -> Void
    ) {
        if abs(panelHeight - height) > 0.5 {
            panelHeight = height
            invalidateIntrinsicContentSize()
        }
        hostingController.rootView = AnyView(
            DynamicInlineCommentEmotePicker(
                emotes: emotes,
                onSelect: insertEmote
            )
        )
    }
}

struct DynamicComposerLayout {
    let bottomSafeArea: CGFloat
    let isCompact: Bool
    let isComposing: Bool
    let usesTelegramInputStyle: Bool

    var usesCompactInsets: Bool {
        isCompact && (!isComposing || usesTelegramInputStyle) && bottomSafeArea > 0
    }

    var horizontalPadding: CGFloat { usesCompactInsets ? 26 : 8 }

    var bottomPadding: CGFloat {
        if isComposing {
            return 8
        }

        return usesCompactInsets
            ? (usesTelegramInputStyle ? 10 : 8) + min(bottomSafeArea, 20) - bottomSafeArea
            : 8
    }
}

struct DynamicDetailBottomInteractionBar: ToolbarContent {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor

    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let commentCount: Int
    let canComment: Bool
    let openComment: () -> Void

    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var errorMessage: String?

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        openComment: @escaping () -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
        self.openComment = openComment
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
    }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            likeButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            commentButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            shareButton
        }
    }

    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(likeState.isLiked ? appTintColor : .primary)
        .disabled(isMutatingLike)
        .accessibilityLabel(likeState.isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(likeState.isLiked ? "已点赞" : "未点赞")，\(likeState.likeCount) 个赞")
        .accessibilityAddTraits(likeState.isLiked ? .isSelected : [])
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var commentButton: some View {
        Button(action: openComment) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.body)
                Text("点击发送电波")
                    .font(.body)
            }
            .padding(.horizontal, 6)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(.primary)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("评论")
        .accessibilityValue("共 \(commentCount) 条")
        .disabled(!canComment)
    }

    private var shareButton: some View {
        ShareLink(item: dynamicShareURL) {
            Image(systemName: "square.and.arrow.up")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(.primary)
        .accessibilityLabel("分享动态")
    }

    private var dynamicShareURL: URL {
        URL(string: "https://t.bilibili.com/\(display.dynamicID)")!
    }

    private func toggleLike() {
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        guard account.isLoggedIn, !isMutatingLike else {
            errorMessage = account.isLoggedIn ? nil : "请先登录账号"
            return
        }

        let previousState = likeState
        let targetState = previousState.toggled()
        isMutatingLike = true
        likeState = targetState
        Task { @MainActor in
            do {
                try await dependencies.api.setDynamicLike(
                    dynamicID: display.dynamicID,
                    liked: targetState.isLiked
                )
                Haptics.success()
            } catch {
                likeState = previousState
                errorMessage = error.localizedDescription
            }
            isMutatingLike = false
        }
    }

}

struct DynamicDetailComposerBottomBar: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let bottomSafeArea: CGFloat
    let keyboardHeight: CGFloat

    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let commentCount: Int
    let canComment: Bool
    let usesTelegramInputStyle: Bool
    @Binding var draft: String
    let api: BiliAPIClient
    let submit: (String, [DynamicCommentImage]?) async throws -> Void

    @State private var composerState = DynamicCommentComposerState.idle
    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var selectedPhotos = [PhotosPickerItem]()
    @State private var attachedImageDatas = [Data]()
    @State private var isLoadingImages = false
    @State private var emotes = [BiliInlineEmote]()
    @State private var activePanel: DynamicDetailComposerPanel?
    @State private var activePanelHeight: CGFloat = 300
    @State private var mostRecentKeyboardHeight: CGFloat?
    @State private var editorHeight: CGFloat = 40
    @State private var showsFullPhotoPicker = false
    @State private var message: String?
    @State private var isNativeEditorFocused = false
    @FocusState private var isEditorFocused: Bool

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        usesTelegramInputStyle: Bool = false,
        bottomSafeArea: CGFloat = 0,
        keyboardHeight: CGFloat = 0,
        draft: Binding<String>,
        api: BiliAPIClient,
        submit: @escaping (String, [DynamicCommentImage]?) async throws -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
        self.usesTelegramInputStyle = usesTelegramInputStyle
        self.bottomSafeArea = bottomSafeArea
        self.keyboardHeight = keyboardHeight
        self._draft = draft
        self.api = api
        self.submit = submit
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
    }

    private var isComposing: Bool {
        switch composerState {
        case .idle:
            return false
        case .composing, .replying, .sending, .failed:
            return true
        }
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !normalizedDraft.isEmpty && composerState != .sending && !isLoadingImages
    }

    private var layout: DynamicComposerLayout {
        DynamicComposerLayout(
            bottomSafeArea: bottomSafeArea,
            isCompact: horizontalSizeClass == .compact,
            isComposing: isComposing,
            usesTelegramInputStyle: usesTelegramInputStyle
        )
    }

    private var usesEmoteInputView: Bool {
        usesTelegramInputStyle && activePanel == .emotes
    }

    private var emoteInputHeight: CGFloat {
        if keyboardHeight > bottomSafeArea {
            return keyboardHeight
        }
        return mostRecentKeyboardHeight ?? 300
    }

    var body: some View {
        VStack(spacing: 8) {
            if usesTelegramInputStyle {
                telegramComposer
            } else if isComposing {
                expandedComposer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                collapsedBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, presentsFullWidthEmotePanel ? 0 : layout.horizontalPadding)
        .padding(.top, 3)
        .padding(.bottom, presentsFullWidthEmotePanel ? 0 : layout.bottomPadding)
        .animation(.smooth, value: isComposing)
        .onChange(of: keyboardHeight, initial: true) { _, height in
            guard height > bottomSafeArea else { return }
            mostRecentKeyboardHeight = height
        }
        .onChange(of: selectedPhotos) { _, items in
            loadSelectedPhotos(items)
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            guard !usesTelegramInputStyle else { return }
            handleEditorFocusChange(isFocused)
        }
        .onChange(of: isNativeEditorFocused) { _, isFocused in
            guard usesTelegramInputStyle else { return }
            handleEditorFocusChange(isFocused)
        }
        .task {
            guard emotes.isEmpty else { return }
            emotes = (try? await api.fetchCommentEmotes()) ?? []
        }
        .onChange(of: sourceLikeState) { _, state in
            guard !isMutatingLike else { return }
            likeState = state
        }
        .alert("操作提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "请稍后重试")
        }
        .photosPicker(
            isPresented: $showsFullPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 9,
            matching: .images,
            preferredItemEncoding: .current
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dynamic.detail.composer.bottomBar")
    }

    private var collapsedBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                if usesTelegramInputStyle {
                    shareButton
                } else {
                    likeButton
                }

                Button(action: beginComposing) {
                    Label("说点什么…", systemImage: "bubble.left")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
                .disabled(!canComment)
                .accessibilityLabel("发表评论")
                .accessibilityValue("共 \(commentCount) 条评论")
                .accessibilityIdentifier("dynamic.detail.composer.comment")

                if usesTelegramInputStyle {
                    likeButton
                } else {
                    favoriteButton
                }
            }
        }
    }

    private var telegramComposer: some View {
        VStack(spacing: 8) {
            GlassEffectContainer(spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    shareButton
                    telegramCommentControl
                    telegramTrailingButton
                }
            }
            .padding(.horizontal, presentsFullWidthEmotePanel ? layout.horizontalPadding : 0)

            activeComposerPanel
        }
    }

    private var presentsFullWidthEmotePanel: Bool {
        usesTelegramInputStyle && activePanel == .emotes
    }

    @ViewBuilder
    private var telegramCommentControl: some View {
        if isComposing {
            HStack(alignment: .center, spacing: 2) {
                DynamicComposerTextView(
                    text: $draft,
                    isFocused: isNativeEditorFocused,
                    usesEmoteInputView: usesEmoteInputView,
                    emoteInputHeight: emoteInputHeight,
                    emotes: emotes,
                    onFocusChange: { isNativeEditorFocused = $0 },
                    onHeightChange: { editorHeight = $0 }
                )
                .frame(height: editorHeight)
                .padding(.leading, 12)
                .padding(.vertical, 2)

                composerPanelButton(.photos, systemImage: "photo")
                composerPanelButton(.emotes, systemImage: "face.smiling")
            }
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, minHeight: 40)
            .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Button(action: beginComposing) {
                Label("说点什么…", systemImage: "bubble.left")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .disabled(!canComment)
            .accessibilityLabel("发表评论")
            .accessibilityValue("共 \(commentCount) 条评论")
            .accessibilityIdentifier("dynamic.detail.composer.comment")
        }
    }

    private var telegramTrailingButton: some View {
        Group {
            if isComposing && canSend {
                sendButton
            } else {
                likeButton
            }
        }
    }

    private var expandedComposer: some View {
        VStack(spacing: 8) {
            attachmentPreview

            GlassEffectContainer(spacing: 6) {
                HStack(alignment: .bottom, spacing: 6) {
                    editorSurface
                    sendButton
                }
            }

            activeComposerPanel
        }
    }

    @ViewBuilder
    private var activeComposerPanel: some View {
        if activePanel == .emotes, !usesEmoteInputView {
            DynamicInlineCommentEmotePicker(
                emotes: emotes,
                bottomSafeAreaInset: bottomSafeArea,
                onSelect: insertEmote
            )
            .frame(height: activePanelHeight + bottomSafeArea)
            .padding(.bottom, -bottomSafeArea)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if activePanel == .photos {
            DynamicInlinePhotoPickerPanel(
                selection: $selectedPhotos,
                showsFullPicker: $showsFullPhotoPicker,
                onDismiss: dismissActivePanel
            )
            .frame(height: activePanelHeight)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func composerPanelButton(
        _ panel: DynamicDetailComposerPanel,
        systemImage: String
    ) -> some View {
        Button {
            togglePanel(panel)
        } label: {
            Image(systemName: activePanel == panel
                ? (panel == .photos ? "photo.fill" : "face.smiling.inverse")
                : systemImage)
                .frame(width: 32, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(activePanel == panel ? appTintColor : .secondary)
        .accessibilityLabel(panel == .photos ? "添加图片" : "选择表情")
    }

    private var editorSurface: some View {
        HStack(alignment: .bottom, spacing: 2) {
            TextField("发表评论", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isEditorFocused)
                .textFieldStyle(.plain)
                .padding(.leading, 12)
                .padding(.vertical, 11)
                .accessibilityLabel("评论内容")
                .accessibilityIdentifier("dynamic.detail.composer.editor")

            Button {
                togglePanel(.photos)
            } label: {
                Image(systemName: activePanel == .photos ? "photo.fill" : "photo")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(activePanel == .photos ? appTintColor : .secondary)
            .accessibilityLabel(activePanel == .photos ? "收起照片选择器" : "添加图片")

            Button {
                togglePanel(.emotes)
            } label: {
                Image(systemName: activePanel == .emotes ? "face.smiling.inverse" : "face.smiling")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(activePanel == .emotes ? appTintColor : .secondary)
            .accessibilityLabel(activePanel == .emotes ? "收起表情选择器" : "选择表情")
        }
        .padding(.trailing, 2)
        .frame(minHeight: 40)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var sendButton: some View {
        Button(action: submitDraft) {
            Group {
                if composerState == .sending || isLoadingImages {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(appTintColor).interactive(), in: Circle())
        .disabled(!canSend)
        .accessibilityLabel(composerState == .sending ? "正在发送评论" : "发送评论")
        .accessibilityIdentifier("dynamic.detail.composer.send")
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if !attachedImageDatas.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
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
            .padding(.horizontal, 8)
        }
    }

    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.body)
                .frame(width: 40, height: 40)
                .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .foregroundStyle(likeState.isLiked ? appTintColor : .primary)
        .disabled(isMutatingLike)
        .accessibilityLabel(likeState.isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(likeState.isLiked ? "已点赞" : "未点赞")，\(likeState.likeCount) 个赞")
        .accessibilityAddTraits(likeState.isLiked ? .isSelected : [])
        .accessibilityIdentifier("dynamic.detail.composer.like")
        .contentTransition(.symbolEffect(.replace))
    }

    private var favoriteButton: some View {
        Button {
            message = "动态收藏暂未接入"
        } label: {
            Image(systemName: "star")
                .font(.body)
                .frame(width: 40, height: 40)
                .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .foregroundStyle(.secondary)
        .accessibilityLabel("收藏")
        .accessibilityValue("动态收藏暂未接入")
        .accessibilityIdentifier("dynamic.detail.composer.favorite")
    }

    private var shareButton: some View {
        ShareLink(item: dynamicShareURL) {
            Image(systemName: "square.and.arrow.up")
                .font(.body)
                .frame(width: 40, height: 40)
                .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .foregroundStyle(.primary)
        .accessibilityLabel("分享动态")
        .accessibilityIdentifier("dynamic.detail.composer.share")
    }

    private var dynamicShareURL: URL {
        URL(string: "https://t.bilibili.com/\(display.dynamicID)")!
    }

    private var sourceLikeState: DynamicLikeDisplayState {
        DynamicLikeDisplayState(isLiked: initialIsLiked, likeCount: initialLikeCount)
    }

    private func beginComposing() {
        guard canComment else { return }
        composerState = .composing
        activePanel = nil
        Task { @MainActor in
            await Task.yield()
            setEditorFocused(true)
        }
    }

    private func dismissActivePanel() {
        withAnimation(.smooth) {
            activePanel = nil
        }
        setEditorFocused(true)
    }

    private func insertEmote(_ token: String) {
        draft += token
    }

    private func togglePanel(_ panel: DynamicDetailComposerPanel) {
        let shouldPresent = activePanel != panel
        if panel == .emotes, usesTelegramInputStyle {
            withAnimation(.smooth) {
                activePanel = shouldPresent ? .emotes : nil
            }
            if !shouldPresent {
                composerState = .composing
                setEditorFocused(true)
            }
            return
        }

        if shouldPresent {
            activePanelHeight = switch panel {
            case .emotes:
                keyboardHeight > bottomSafeArea
                    ? keyboardHeight
                    : (mostRecentKeyboardHeight ?? 300)
            case .photos:
                300
            }
        }
        withAnimation(.smooth) {
            activePanel = shouldPresent ? panel : nil
        }
        if shouldPresent {
            setEditorFocused(false)
        } else {
            composerState = .composing
            setEditorFocused(true)
        }
    }

    private func setEditorFocused(_ isFocused: Bool) {
        if usesTelegramInputStyle {
            isNativeEditorFocused = isFocused
        } else {
            isEditorFocused = isFocused
        }
    }

    private func handleEditorFocusChange(_ isFocused: Bool) {
        guard isFocused else {
            collapseIfPossible()
            return
        }
        if !usesEmoteInputView {
            activePanel = nil
        }
    }

    private func collapseIfPossible() {
        guard activePanel == nil,
              normalizedDraft.isEmpty,
              attachedImageDatas.isEmpty,
              composerState != .sending
        else { return }
        composerState = .idle
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            isLoadingImages = false
            return
        }
        isLoadingImages = true
        Task { @MainActor in
            var imageDatas = [Data]()
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpegData = image.jpegData(compressionQuality: 0.9)
                else { continue }
                imageDatas.append(jpegData)
            }
            attachedImageDatas = imageDatas
            isLoadingImages = false
            activePanel = nil
            setEditorFocused(true)
        }
    }

    private func submitDraft() {
        let messageText = normalizedDraft
        guard !messageText.isEmpty, composerState != .sending, !isLoadingImages else { return }
        composerState = .sending
        Task { @MainActor in
            do {
                var pictures: [DynamicCommentImage]?
                if !attachedImageDatas.isEmpty {
                    pictures = []
                    for imageData in attachedImageDatas {
                        pictures?.append(try await api.uploadDynamicCommentImage(imageData))
                    }
                }
                try await submit(messageText, pictures)
                draft = ""
                selectedPhotos = []
                attachedImageDatas = []
                activePanel = nil
                setEditorFocused(false)
                composerState = .idle
                Haptics.success()
            } catch {
                composerState = .failed(message: error.localizedDescription)
                message = error.localizedDescription
            }
        }
    }

    private func toggleLike() {
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        guard account.isLoggedIn else {
            message = "请先登录账号"
            return
        }
        guard !isMutatingLike else { return }

        let previousState = likeState
        let targetState = previousState.toggled()
        isMutatingLike = true
        withAnimation(.snappy(duration: 0.2)) {
            likeState = targetState
        }
        Task { @MainActor in
            do {
                try await dependencies.api.setDynamicLike(
                    dynamicID: display.dynamicID,
                    liked: targetState.isLiked
                )
                Haptics.success()
            } catch {
                withAnimation(.snappy(duration: 0.2)) {
                    likeState = previousState
                }
                message = error.localizedDescription
            }
            isMutatingLike = false
        }
    }
}

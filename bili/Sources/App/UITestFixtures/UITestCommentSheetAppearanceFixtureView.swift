#if DEBUG
import SwiftUI
import UIKit

/// Models RootTabView's split between content appearance and video status-bar contrast.
struct UITestCommentSheetAppearanceFixtureView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var isPresented = false
    @State private var composerTarget: DynamicCommentComposerTarget?
    @StateObject private var drafts = RichCommentDraftStore()
    @State private var contentColorScheme: ColorScheme
    private let hostColorScheme: ColorScheme

    init() {
        let startsDark = ProcessInfo.processInfo.arguments.contains("--comment-appearance-dark")
        _contentColorScheme = State(initialValue: startsDark ? .dark : .light)
        hostColorScheme = startsDark ? .light : .dark
    }

    var body: some View {
        NavigationStack {
            VStack {
                Button("打开评论面板") { isPresented = true }
                    .accessibilityIdentifier("comment.appearance.open")
                Button("打开回复输入框") { composerTarget = .dynamic }
                    .accessibilityIdentifier("comment.appearance.composer")
                Button("切换 App 外观") {
                    contentColorScheme = contentColorScheme == .light ? .dark : .light
                }
                .accessibilityIdentifier("comment.appearance.rootToggle")
            }
            .background {
                RichCommentComposerPresenter(
                    target: $composerTarget,
                    draft: { drafts.binding(for: $0) },
                    api: dependencies.api,
                    submit: { _, _, _ in }
                )
                .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, contentColorScheme)
        .preferredColorScheme(hostColorScheme)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        BiliEmoteText(
                            content: nil,
                            plainText: "评论正文：拉大面板后仍应清晰可读。\n中文 English 123 🐈",
                            textColor: .primary
                        )
                        .accessibilityIdentifier("comment.appearance.body")

                        CommentSheetAppearanceProbe()
                            .frame(height: 30)

                        Button("切换评论外观") {
                            contentColorScheme = contentColorScheme == .light ? .dark : .light
                        }
                        .accessibilityIdentifier("comment.appearance.toggle")
                    }
                    .padding(20)
                }
                .navigationTitle("评论外观验证")
                .navigationBarTitleDisplayMode(.inline)
            }
            .commentSheetPresentation()
        }
        .environment(\.appContentColorScheme, contentColorScheme)
    }
}

struct CommentSheetAppearanceProbe: UIViewRepresentable {
    @Environment(\.colorScheme) private var swiftUIStyle
    var identifier = "comment.appearance.nativeStyle"
    func makeUIView(context: Context) -> CommentSheetAppearanceProbeLabel {
        let label = CommentSheetAppearanceProbeLabel()
        label.accessibilityIdentifier = identifier
        label.swiftUIStyle = swiftUIStyle
        label.refreshAppearance()
        return label
    }

    func updateUIView(_ view: CommentSheetAppearanceProbeLabel, context: Context) {
        view.swiftUIStyle = swiftUIStyle
        view.refreshAppearance()
    }
}

final class CommentSheetAppearanceProbeLabel: UILabel {
    var swiftUIStyle: ColorScheme = .light
    override init(frame: CGRect) {
        super.init(frame: frame)
        textColor = .label
        backgroundColor = .systemBackground
        isAccessibilityElement = true
        accessibilityIdentifier = "comment.appearance.nativeStyle"
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: CommentSheetAppearanceProbeLabel, _: UITraitCollection) in
            view.refreshAppearance()
        }
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshAppearance()
    }

    func refreshAppearance() {
        switch traitCollection.userInterfaceStyle {
        case .light: text = "light/\(swiftUIStyle == .dark ? "dark" : "light")"
        case .dark: text = "dark/\(swiftUIStyle == .dark ? "dark" : "light")"
        default: text = "unspecified"
        }
    }
}
#endif

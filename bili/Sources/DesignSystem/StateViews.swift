import SwiftUI

struct DelayedLoadingContent<Content: View>: View {
    @State private var isVisible = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            // Keep a real view in the hierarchy while the delayed content is
            // hidden. An empty Group can prevent lifecycle tasks from running
            // when it is the only child of a lazily mounted tab.
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)

            if isVisible {
                content()
            }
        }
        .task {
            isVisible = false
            do {
                try await Task.sleep(for: LoadingPresentationPolicy.minimumIndicatorDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isVisible = true
        }
    }
}

struct ErrorStateView: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        BiliContentStateSurface(
            title: title,
            message: message,
            systemImage: "exclamationmark.triangle",
            tint: .orange
        ) {
            if let retry {
                Button(action: retry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(appTintColor)
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        BiliContentStateSurface(
            title: title,
            message: message,
            systemImage: systemImage,
            tint: .secondary
        )
    }
}

struct InlineLoadingStateView: View {
    var title: String
    var systemImage: String = "arrow.triangle.2.circlepath"

    var body: some View {
        DelayedLoadingContent {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)

                Label(title, systemImage: systemImage)
                    .labelStyle(.titleOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityLabel(title)
        }
    }
}

struct InitialContentLoadingView: View {
    let title: String
    var topPadding: CGFloat = 96

    var body: some View {
        InlineLoadingStateView(title: title)
            .frame(maxWidth: .infinity)
            .padding(.top, topPadding)
            .allowsHitTesting(false)
    }
}

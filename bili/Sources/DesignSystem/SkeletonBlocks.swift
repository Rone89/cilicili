import SwiftUI

struct SkeletonLoadingContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .compositingGroup()
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let bandWidth = max(proxy.size.width * 0.48, 88)

                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.52),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: bandWidth)
                        .offset(
                            x: isAnimating
                                ? proxy.size.width + bandWidth
                                : -bandWidth
                        )
                        .blendMode(.sourceAtop)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .task(id: reduceMotion) {
                isAnimating = false
                guard !reduceMotion else { return }
                await Task.yield()
                withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

struct SkeletonSurface: View {
    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill).opacity(0.64))
            .accessibilityHidden(true)
    }
}

struct SkeletonBlock: View {
    enum Shape {
        case rounded(CGFloat)
        case capsule
        case circle
    }

    var width: CGFloat?
    var height: CGFloat
    var shape: Shape = .rounded(8)

    var body: some View {
        block
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var block: some View {
        switch shape {
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.64))
        case .capsule:
            Capsule()
                .fill(Color(.tertiarySystemFill).opacity(0.64))
        case .circle:
            Circle()
                .fill(Color(.tertiarySystemFill).opacity(0.64))
        }
    }
}

struct SkeletonAspectBlock: View {
    var aspectRatio: CGFloat = 16 / 9
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.tertiarySystemFill).opacity(0.64))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

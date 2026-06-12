import SwiftUI

private struct RootNavigationTitleHiddenKey: EnvironmentKey {
    static let defaultValue = Binding<Bool>.constant(false)
}

private extension EnvironmentValues {
    var rootNavigationTitleHidden: Binding<Bool> {
        get { self[RootNavigationTitleHiddenKey.self] }
        set { self[RootNavigationTitleHiddenKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func rootFloatingTabBarContentPadding(extra: CGFloat = 0) -> some View {
        safeAreaPadding(.bottom, RootFloatingTabBarMetrics.contentBottomPadding + extra)
    }

    @ViewBuilder
    func nativeTopNavigationChrome() -> some View {
        toolbarBackground(.automatic, for: .navigationBar)
    }

    @ViewBuilder
    func rootNavigationTitle(_ title: String) -> some View {
        rootNavigationTitle(title) {
            EmptyView()
        }
    }

    @ViewBuilder
    func rootNavigationTitle<Accessory: View>(
        _ title: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(RootFloatingNavigationTitleModifier(title: title, accessory: accessory))
    }

    @ViewBuilder
    func hiddenRootNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    func hiddenInlineNavigationTitle() -> some View {
        navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    func nativeTopScrollEdgeEffect() -> some View {
        modifier(TopScrollEdgeEffect())
    }

    @ViewBuilder
    func liquidGlassTabBarBackground(isDark: Bool = false) -> some View {
        self
    }

    @ViewBuilder
    func biliGlassEffect<S: Shape>(
        tint: Color = Color(.systemBackground).opacity(0.18),
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        glassEffect(
            .regular
                .tint(tint)
                .interactive(interactive),
            in: shape
        )
    }

    @ViewBuilder
    func biliGlassButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }

    @ViewBuilder
    func biliPlayerGlassButtonStyle(prominent: Bool = false) -> some View {
        buttonBorderShape(.capsule)
            .biliGlassButtonStyle(prominent: prominent)
    }

    @ViewBuilder
    func biliPlayerYouTubePillStyle(prominent: Bool = false) -> some View {
        buttonStyle(.plain)
            .background {
                Capsule()
                    .fill(.black.opacity(prominent ? 0.48 : 0.34))
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(prominent ? 0.12 : 0.08), lineWidth: 0.5)
            }
            .contentShape(Capsule())
    }
}

struct TopScrollEdgeEffect: ViewModifier {
    @Environment(\.rootNavigationTitleHidden) private var rootNavigationTitleHidden

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 18
            } action: { _, isHidden in
                guard rootNavigationTitleHidden.wrappedValue != isHidden else { return }
                withAnimation(.smooth(duration: 0.18)) {
                    rootNavigationTitleHidden.wrappedValue = isHidden
                }
            }
    }
}

private struct RootFloatingNavigationTitleModifier<Accessory: View>: ViewModifier {
    let title: String
    let accessory: () -> Accessory
    @State private var isTitleHidden = false

    func body(content: Content) -> some View {
        content
            .environment(\.rootNavigationTitleHidden, $isTitleHidden)
            .hiddenRootNavigationTitle(title)
            .safeAreaBar(edge: .top, alignment: .leading, spacing: -4) {
                RootFloatingNavigationTitle(
                    title: title,
                    isTitleHidden: isTitleHidden,
                    accessory: accessory
                )
            }
    }
}

private struct RootFloatingNavigationTitle<Accessory: View>: View {
    let title: String
    let isTitleHidden: Bool
    let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .opacity(isTitleHidden ? 0 : 1)
                .scaleEffect(isTitleHidden ? 0.92 : 1, anchor: .leading)
                .clipped()

            Spacer(minLength: 12)

            accessory()
                .opacity(isTitleHidden ? 0 : 1)
                .scaleEffect(isTitleHidden ? 0.92 : 1, anchor: .trailing)
                .allowsHitTesting(!isTitleHidden)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, -6)
        .padding(.bottom, 3)
    }
}

enum RootFloatingTabBarMetrics {
    static let contentBottomPadding: CGFloat = 92
}

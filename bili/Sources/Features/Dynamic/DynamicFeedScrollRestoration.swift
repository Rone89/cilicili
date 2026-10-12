import SwiftUI

struct DynamicFeedScrollRestoration: ViewModifier {
    let viewModel: DynamicViewModel
    let isEnabled: Bool
    @Environment(\.rootTabScrollRequest) private var rootTabScrollRequest
    @State private var position = ScrollPosition()
    @State private var samples = OffsetSamples()

    private final class OffsetSamples {
        var current: CGFloat = 0
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    samples.current = offset
                }
                .onAppear {
                    samples.current = viewModel.savedScrollOffset
                    position.scrollTo(y: viewModel.savedScrollOffset)
                }
                .onDisappear { viewModel.savedScrollOffset = samples.current }
                .onChange(of: rootTabScrollRequest) { _, request in
                    if request != nil {
                        viewModel.savedScrollOffset = 0
                        samples.current = 0
                    }
                }
        } else {
            content
        }
    }
}

import SwiftUI

struct DynamicFeedScrollRestoration: ViewModifier {
    let viewModel: DynamicViewModel
    let isEnabled: Bool
    @Environment(\.rootTabScrollRequest) private var rootTabScrollRequest
    @State private var position = ScrollPosition()
    @State private var samples = DynamicFeedScrollState()

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    samples.update(offset, for: viewModel)
                }
                .onChange(of: ObjectIdentifier(viewModel)) { _, _ in
                    restorePosition()
                }
                .onAppear { restorePosition() }
                .onDisappear { samples.save() }
                .onChange(of: rootTabScrollRequest) { _, request in
                    if request != nil {
                        samples.update(0, for: viewModel)
                        samples.save()
                    }
                }
        } else {
            content
        }
    }

    private func restorePosition() {
        let offset = samples.activate(viewModel)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { position.scrollTo(y: offset) }
    }
}

/// Samples do not publish scroll ticks; switching models saves only the outgoing
/// feed's offset while reusing the same ScrollView and its edge-effect host.
@MainActor
final class DynamicFeedScrollState {
    private weak var model: DynamicViewModel?
    private var current: CGFloat = 0

    func activate(_ next: DynamicViewModel) -> CGFloat {
        if model !== next {
            save()
            model = next
            current = next.savedScrollOffset
        }
        return current
    }

    func update(_ offset: CGFloat, for source: DynamicViewModel) {
        guard model === source else { return }
        current = max(0, offset)
    }

    func save() {
        model?.savedScrollOffset = current
    }
}

import SwiftUI

struct ScrollableTabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                titleView
                Spacer(minLength: 12)
                trailing()
            }

            VStack(alignment: .leading, spacing: 12) {
                titleView
                trailing()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var titleView: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

extension ScrollableTabHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

private struct RootTopLevelNavigationChrome: ViewModifier {
    let title: String
    let isEnabled: Bool
    let keepsToolbarVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            if keepsToolbarVisible {
                content
                    .toolbarVisibility(.visible, for: .navigationBar)
                    .toolbarBackground(.automatic, for: .navigationBar)
                    .navigationTitle("")
                    .toolbarTitleDisplayMode(.inline)
            } else {
                content.hiddenRootNavigationTitle("")
            }
        } else {
            content
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarBackground(.automatic, for: .navigationBar)
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
        }
    }
}

extension View {
    func rootTopLevelNavigationChrome(
        title: String,
        isEnabled: Bool,
        keepsToolbarVisible: Bool = false
    ) -> some View {
        modifier(
            RootTopLevelNavigationChrome(
                title: title,
                isEnabled: isEnabled,
                keepsToolbarVisible: keepsToolbarVisible
            )
        )
    }
}

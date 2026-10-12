import SwiftUI
import UIKit

/// Keep UIKit's control identity and let touch selection use its native animation.
struct DynamicFeedToolbarPicker: UIViewRepresentable {
    @Binding var selection: DynamicFeedKind

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: DynamicFeedKind.allCases.map(\.title))
        control.selectedSegmentIndex = DynamicFeedKind.allCases.firstIndex(of: selection) ?? 0
        control.addTarget(context.coordinator, action: #selector(Coordinator.selectionChanged(_:)), for: .valueChanged)
        control.accessibilityLabel = "动态内容"
        control.accessibilityIdentifier = "dynamic.feedPicker"
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        let index = DynamicFeedKind.allCases.firstIndex(of: selection) ?? 0
        // Writing the same selected index during feed updates can interrupt the
        // animation already started by UISegmentedControl's touch handling.
        if control.selectedSegmentIndex != index {
            control.selectedSegmentIndex = index
        }
        control.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 44)
    }

    final class Coordinator: NSObject {
        var selection: Binding<DynamicFeedKind>

        init(selection: Binding<DynamicFeedKind>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ control: UISegmentedControl) {
            let kinds = DynamicFeedKind.allCases
            guard kinds.indices.contains(control.selectedSegmentIndex) else { return }
            let kind = kinds[control.selectedSegmentIndex]
            if selection.wrappedValue != kind { selection.wrappedValue = kind }
        }
    }
}

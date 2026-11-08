import SwiftUI
import UIKit

/// Keep UIKit's control identity and let touch selection use its native animation.
/// Only the configured visible kinds become segments.
struct DynamicFeedToolbarPicker: UIViewRepresentable {
    let kinds: [DynamicFeedKind]
    @Binding var selection: DynamicFeedKind

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, kinds: kinds)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: kinds.map(\.title))
        control.selectedSegmentIndex = kinds.firstIndex(of: selection) ?? 0
        control.addTarget(context.coordinator, action: #selector(Coordinator.selectionChanged(_:)), for: .valueChanged)
        control.accessibilityLabel = "动态内容"
        control.accessibilityIdentifier = "dynamic.feedPicker"
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.kinds = kinds
        if control.numberOfSegments != kinds.count
            || control.titleForSegment(at: 0) != kinds.first?.title {
            control.removeAllSegments()
            for kind in kinds {
                control.insertSegment(withTitle: kind.title, at: control.numberOfSegments, animated: false)
            }
        }
        let index = kinds.firstIndex(of: selection) ?? 0
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
        var kinds: [DynamicFeedKind]

        init(selection: Binding<DynamicFeedKind>, kinds: [DynamicFeedKind]) {
            self.selection = selection
            self.kinds = kinds
        }

        @objc func selectionChanged(_ control: UISegmentedControl) {
            guard kinds.indices.contains(control.selectedSegmentIndex) else { return }
            let kind = kinds[control.selectedSegmentIndex]
            if selection.wrappedValue != kind { selection.wrappedValue = kind }
        }
    }
}

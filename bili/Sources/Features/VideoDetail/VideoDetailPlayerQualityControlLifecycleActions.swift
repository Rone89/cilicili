import Foundation

struct VideoDetailPlayerQualityControlLifecycleActions {
    let onPresentationChange: (Bool) -> Void

    func handlePresentationChanged(_ isPresented: Bool) {
        onPresentationChange(isPresented)
    }

    func handleDisappear() {
        onPresentationChange(false)
    }
}

import Foundation

struct PortraitCommentsSheetLifecycleActions {
    let actions: PortraitCommentsSheetActions

    func beginInitialCommentsLoad() {
        actions.beginInitialCommentsLoad()
    }

    func retryComments() async {
        await actions.retryComments()
    }
}

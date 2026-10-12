import Foundation

extension VideoDetailViewModel {
    func failCommentPageLoad(_ error: Error, presentsErrors: Bool) {
        if !presentsErrors || !comments.isEmpty {
            commentState = .loaded
            commentLoadMoreState = .failed(error.localizedDescription)
        } else {
            commentState = .failed(error.localizedDescription)
            commentLoadMoreState = .idle
        }
    }
}

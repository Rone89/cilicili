import Foundation

extension VideoDetailViewModel {
    func shouldUseStagedStartupVariant(for _: PlayVariant) -> Bool {
        false
    }

    func stagedStartupDisabledReason(for _: PlayVariant) -> String? {
        "qualityPriority"
    }

    func shouldScheduleStagedStartupUpgrade(from _: PlayVariant, to _: PlayVariant) -> Bool {
        false
    }
}

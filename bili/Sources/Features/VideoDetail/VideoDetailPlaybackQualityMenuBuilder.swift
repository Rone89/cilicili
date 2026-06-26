import Foundation

enum VideoDetailPlaybackQualityMenuBuilder {
    static func inlineQualityButtonTitle(
        selectedPlayVariant: PlayVariant?,
        isSupplementingPlayQualities _: Bool,
        isSwitchingPlayQuality: Bool
    ) -> String {
        if isSwitchingPlayQuality {
            return "切换中"
        }
        return selectedPlayVariant?.compactAccessoryTitle ?? "清晰度"
    }

    static func accessoryQualityButtonTitle(
        selectedPlayVariant: PlayVariant?,
        isSupplementingPlayQualities _: Bool,
        isSwitchingPlayQuality: Bool
    ) -> String {
        if isSwitchingPlayQuality {
            return "切换中"
        }
        return selectedPlayVariant?.compactAccessoryTitle ?? "清晰度"
    }

    static func makeQualityMenuItems(
        playVariants: [PlayVariant],
        selectedPlayVariant: PlayVariant?,
        pendingPlayVariantID: String?,
        isSwitchingPlayQuality: Bool
    ) -> [VideoDetailPlaybackQualityMenuItem] {
        compactQualityVariants(from: playVariants).map { variant in
            let systemImage: String
            if isPending(variant, pendingPlayVariantID: pendingPlayVariantID, playVariants: playVariants) {
                systemImage = "arrow.triangle.2.circlepath"
            } else if selectedPlayVariant?.quality == variant.quality {
                systemImage = "checkmark"
            } else {
                systemImage = variant.isPlayable ? "circle" : "lock.fill"
            }
            return VideoDetailPlaybackQualityMenuItem(
                variant: variant,
                title: variant.qualityMenuTitle,
                systemImage: systemImage,
                isDisabled: !variant.isPlayable || isSwitchingPlayQuality
            )
        }
    }

    private static func compactQualityVariants(from playVariants: [PlayVariant]) -> [PlayVariant] {
        var seenQualities = Set<Int>()
        var result = [PlayVariant]()
        for variant in playVariants {
            guard seenQualities.insert(variant.quality).inserted else { continue }
            result.append(variant)
        }
        return result
    }

    private static func isPending(
        _ menuVariant: PlayVariant,
        pendingPlayVariantID: String?,
        playVariants: [PlayVariant]
    ) -> Bool {
        guard let pendingPlayVariantID else { return false }
        if pendingPlayVariantID == menuVariant.id { return true }
        return playVariants.first { $0.id == pendingPlayVariantID }?.quality == menuVariant.quality
    }
}

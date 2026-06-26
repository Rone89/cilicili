import SwiftUI

extension MinePlaybackSettingsView {
    var playbackPreferenceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("当前策略", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(libraryStore.playbackAutoOptimizationMode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(libraryStore.playbackAutoOptimizationMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                MinePlaybackPreferenceChip(
                    title: LibraryStore.videoQualityTitle(libraryStore.preferredVideoQuality),
                    systemImage: "play.rectangle"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.videoCodecPreference.title,
                    systemImage: "film.stack"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.playbackStreamSourcePreference.title,
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.playerRenderingEnginePreference.title,
                    systemImage: "cpu"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.playbackCDNPreference.title,
                    systemImage: "network"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.playbackNetworkAddressFamilyPreference.title,
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }
        }
        .padding(.vertical, 4)
    }
}

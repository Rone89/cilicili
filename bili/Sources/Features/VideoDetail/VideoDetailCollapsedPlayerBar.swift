import SwiftUI

struct VideoDetailCollapsedPlayerBar: View {
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let onNavigateBack: () -> Void
    let onRequestFullscreen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onNavigateBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Button {
                playerViewModel.togglePlayback()
            } label: {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerViewModel.isPlaying ? "暂停" : "播放")

            Text(playerViewModel.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRequestFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全屏")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.84))
        .contentShape(Rectangle())
    }
}

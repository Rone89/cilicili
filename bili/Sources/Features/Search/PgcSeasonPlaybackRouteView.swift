import SwiftUI

struct PgcSeasonPlaybackRouteView: View {
    let route: PgcSeasonRoute
    let onRequestClose: (() -> Void)?
    let onPopOne: (() -> Void)?

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var selectedVideo: VideoItem?
    @State private var reloadRevision = 0
    @State private var state: LoadingState = .idle

    init(
        route: PgcSeasonRoute,
        onRequestClose: (() -> Void)? = nil,
        onPopOne: (() -> Void)? = nil
    ) {
        self.route = route
        self.onRequestClose = onRequestClose
        self.onPopOne = onPopOne
    }

    var body: some View {
        Group {
            if let video = route.episodeSeedVideo ?? selectedVideo {
                VideoDetailView(
                    seedVideo: video,
                    onRequestClose: onRequestClose,
                    onPopOne: onPopOne
                )
                .id(video.id)
            } else {
                PgcSeasonPlaybackRouteLoadingView(
                    route: route,
                    state: state,
                    retry: reload
                )
            }
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(route.id):\(reloadRevision)") {
            await load()
        }
    }

    private func reload() {
        reloadRevision &+= 1
    }

    private func load() async {
        guard route.episodeSeedVideo == nil, selectedVideo == nil else { return }

        state = .loading
        do {
            var season = try await dependencies.api.fetchPgcSeasonInfo(seasonID: route.seasonID, epID: route.episodeID)
            if let seasonID = route.seasonID {
                season = season.withFallbackSeasonID(seasonID)
            }
            guard !Task.isCancelled else { return }
            guard let episode = route.playbackEpisode(in: season),
                  let video = episode.videoItem(in: season) else {
                state = .failed(route.episodeID == nil ? "暂无可播放分集" : "该分集不可播放或已失效")
                return
            }

            selectedVideo = video
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

private struct PgcSeasonPlaybackRouteLoadingView: View {
    let route: PgcSeasonRoute
    let state: LoadingState
    let retry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            if case .failed(let message) = state {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
                if let episodeID = route.episodeID,
                   let url = URL(string: "https://www.bilibili.com/bangumi/play/ep\(episodeID)") {
                    AppLinkButton(url: url) { Text("网页查看") }
                }
            } else {
                ProgressView()
                Text(route.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if route.episodeID != nil {
                Button("返回") { dismiss() }
                    .accessibilityIdentifier("pgc.route.cancel")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityLabel("正在打开番剧")
    }
}

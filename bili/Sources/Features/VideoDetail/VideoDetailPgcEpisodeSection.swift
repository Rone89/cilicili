import SwiftUI

struct VideoDetailPgcEpisodeSection<ActionContent: View>: View {
    let detail: VideoItem
    let api: BiliAPIClient
    let selectEpisode: (VideoItem) -> Void
    @ViewBuilder let actionContent: () -> ActionContent

    @State private var season: PgcSeasonInfo?
    @State private var state: LoadingState = .idle
    @State private var isEpisodeSheetPresented = false

    private var loadID: String {
        "\(detail.pgcSeasonID ?? 0)-\(resolvedEpisodeID ?? 0)-\(detail.cid ?? 0)"
    }

    private var resolvedEpisodeID: Int? {
        detail.pgcEpisodeID ?? detail.bvid.pgcRouteEpisodeID
    }

    private var compactItems: [VideoDetailCompactSelectionItem] {
        guard let season else { return [] }
        return season.selectableEpisodes.map { episode in
            VideoDetailCompactSelectionItem(
                episode: episode,
                season: season,
                isSelected: episode.matches(detail: detail)
            )
        }
    }

    var body: some View {
        Group {
            if let season {
                VStack(alignment: .leading, spacing: 18) {
                    VideoDetailPgcSeasonInfoBlock(
                        season: season,
                        detail: detail
                    )

                    actionContent()

                    if season.selectableEpisodes.count > 1 {
                        VideoDetailCompactEntryButton(
                            sectionTitle: "分集",
                            countUnit: "集",
                            items: compactItems,
                            accessibilityIdentifier: "video.detail.episodeMenu.compact",
                            showsSheet: $isEpisodeSheetPresented
                        )
                    }
                }
            } else if state == .idle || state.isLoading {
                VideoDetailPgcEpisodeLoadingSection()
            } else if case .failed(let message) = state {
                VideoDetailPgcEpisodeFailedSection(message: message) {
                    Task { await load(force: true) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: loadID) {
            await load(force: false)
        }
        .sheet(isPresented: $isEpisodeSheetPresented) {
            if let season {
                VideoDetailCompactSelectionSheet(
                    sectionTitle: "全部分集",
                    items: compactItems,
                    selectItem: { item in
                        guard let video = item.selectVideo else { return }
                        selectEpisode(video)
                    }
                )
            }
        }
    }

    private func load(force: Bool) async {
        guard force || season == nil else { return }
        // Let the foreground detail request resolve CID first. Its response
        // cache can then supply this section without a competing cold request.
        guard detail.cid != nil else { return }
        let epID = resolvedEpisodeID
        guard detail.pgcSeasonID != nil || epID != nil else {
            state = .failed("暂无分集信息")
            return
        }
        state = .loading
        do {
            season = try await api.fetchPgcSeasonInfo(
                seasonID: detail.pgcSeasonID,
                epID: epID
            )
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct VideoDetailPgcEpisodeLoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分集")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                SkeletonBlock(width: 54, height: 13, shape: .capsule)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonBlock(width: 118, height: 56, shape: .rounded(12))
                    }
                }
            }
            .scrollDisabled(true)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("正在加载分集")
    }
}

private struct VideoDetailPgcEpisodeFailedSection: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分集")
                    .font(.headline)
                Spacer()
                Button("重试", action: retry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(appTintColor)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private extension PgcEpisode {
    func matches(detail: VideoItem) -> Bool {
        if let episodeID = detail.pgcEpisodeID ?? detail.bvid.pgcRouteEpisodeID,
           epID == episodeID || idValue == episodeID {
            return true
        }
        if let cid = detail.cid, self.cid == cid {
            return true
        }
        if let bvid = bvid?.trimmedNonEmpty, bvid == detail.bvid {
            return true
        }
        return false
    }
}

private extension String {
    var pgcRouteEpisodeID: Int? {
        guard hasPrefix("ep") else { return nil }
        return Int(dropFirst(2))
    }

    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

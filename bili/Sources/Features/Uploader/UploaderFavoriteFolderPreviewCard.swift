import SwiftUI

struct UploaderFavoriteFolderPreviewCard: View {
    let item: UploaderSpaceFavoritePreview
    @ObservedObject var viewModel: UploaderViewModel

    private var entries: [AccountVideoEntry] {
        viewModel.favoriteFolderPreviews[item.folder.id] ?? []
    }

    private var state: LoadingState {
        viewModel.favoriteFolderPreviewStates[item.folder.id] ?? .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                UploaderFavoriteFolderContentPage(folder: item.folder)
            } label: {
                HStack(spacing: 8) {
                    Text(item.folder.displayTitle).font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        if let isPublic = item.isPublic { Text(isPublic ? "公开" : "私密") }
                        if let count = item.count ?? item.folder.mediaCount {
                            if item.isPublic != nil { Text("·") }
                            Text("\(count) 个内容")
                        }
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开收藏夹内容")

            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    if entries.indices.contains(index) {
                        let entry = entries[index]
                        VideoRouteLink(entry.videoItem) {
                            VStack(alignment: .leading, spacing: 8) {
                                previewCover(entry.pic)
                                Text(entry.title).font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2, reservesSpace: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .overlay {
                                    if index == 0, state == .idle || state.isLoading {
                                        ProgressView().accessibilityLabel("正在加载收藏预览")
                                    }
                                }
                            Text(" ").font(.caption).lineLimit(2, reservesSpace: true)
                                .hidden()
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityHidden(state == .loaded)
                    }
                }
            }

            if case .failed(let message) = state {
                HStack(alignment: .firstTextBaseline) {
                    Text("预览加载失败：\(message)").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("重试") {
                        Task { await viewModel.loadFavoriteFolderPreviews(folderIDs: [item.folder.id], force: true) }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func previewCover(_ urlString: String?) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    CachedRemoteImage(url: urlString.flatMap { URL(string: $0.biliImageThumbnailURL(maxSide: 480)) }, targetPixelSize: 480) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
    }
}

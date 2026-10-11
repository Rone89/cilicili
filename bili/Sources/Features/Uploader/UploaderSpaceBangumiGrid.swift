import SwiftUI

struct UploaderSpaceBangumiGrid: View {
    let items: [UploaderSpaceVideoPreview]
    var loadMore: ((Int?) async -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), alignment: .top), count: 3),
                  alignment: .leading, spacing: 14) {
            ForEach(items, id: \.seasonID) { item in
                UploaderSpaceSeasonPreview(item: item)
                    .task { await loadMore?(item.seasonID) }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct UploaderSpaceSeasonPreview: View {
    @Environment(\.openPgcSeasonRouteAction) private var openSeason
    let item: UploaderSpaceVideoPreview

    var body: some View {
        if let id = item.seasonID {
            let route = PgcSeasonRoute(seasonID: id, title: item.archive.title, cover: item.archive.cover)
            Group {
                if let openSeason {
                    Button { openSeason(route) } label: { label }
                } else { NavigationLink(value: route) { label } }
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(112.0 / 150.0, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        CachedRemoteImage(url: item.archive.cover.flatMap { URL(string: $0.biliImageThumbnailURL(maxSide: 480)) }, targetPixelSize: 480) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { Rectangle().fill(.quaternary) }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            Text(item.archive.title).font(.caption).foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

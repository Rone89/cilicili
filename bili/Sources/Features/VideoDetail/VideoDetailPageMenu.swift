import SwiftUI

struct VideoDetailPageMenu: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var store: VideoDetailPageSelectorRenderStore
    let selectPage: (VideoPage) -> Void

    @State private var isPageSheetPresented = false

    private var compactItems: [VideoDetailCompactSelectionItem] {
        store.pages.map { page in
            VideoDetailCompactSelectionItem(
                page: page,
                isSelected: page.cid == store.selectedCID,
                fallbackCoverURL: store.coverDisplay?.sourceCoverURL?.absoluteString
            )
        }
    }

    var body: some View {
        if store.shouldShowPageSelector {
            Group {
                if libraryStore.videoDetailCompactPageSelectorExperimentEnabled {
                    VideoDetailCompactEntryButton(
                        sectionTitle: "分P",
                        countUnit: "P",
                        items: compactItems,
                        accessibilityIdentifier: "video.detail.pageMenu.compact",
                        showsSheet: $isPageSheetPresented
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        VideoDetailPageMenuHeader(
                            pageCount: store.pages.count,
                            showsPageSheet: $isPageSheetPresented
                        )

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(store.pages) { page in
                                    VideoDetailPageRoute(
                                        page: page,
                                        isSelected: page.cid == store.selectedCID,
                                        selectPage: selectPage
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, -16)
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .frame(height: 54)
                    }
                    .accessibilityIdentifier("video.detail.pageMenu")
                }
            }
            .sheet(isPresented: $isPageSheetPresented) {
                VideoDetailCompactSelectionSheet(
                    sectionTitle: "全部分P",
                    items: compactItems,
                    selectItem: { item in
                        // UGC 条目的 id 即 cid。
                        guard let page = store.pages.first(where: { $0.cid == item.id }) else { return }
                        selectPage(page)
                    }
                )
            }
        }
    }
}

private struct VideoDetailPageMenuHeader: View {
    let pageCount: Int
    @Binding var showsPageSheet: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("分P")
                .font(.headline)

            Text("\(pageCount) P")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showsPageSheet = true
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(180))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("展开全部分P")
        }
    }
}

private struct VideoDetailPageRoute: View {
    let page: VideoPage
    let isSelected: Bool
    let selectPage: (VideoPage) -> Void

    var body: some View {
        if isSelected {
            VideoDetailPageTile(
                page: page,
                isSelected: true,
                width: 124,
                height: 54
            )
        } else {
            Button {
                selectPage(page)
            } label: {
                VideoDetailPageTile(
                    page: page,
                    isSelected: false,
                    width: 124,
                    height: 54
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct VideoDetailPageTile: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let page: VideoPage
    let isSelected: Bool
    let width: CGFloat?
    let height: CGFloat
    let usesGlassBackground: Bool

    init(
        page: VideoPage,
        isSelected: Bool,
        width: CGFloat? = nil,
        height: CGFloat = 56,
        usesGlassBackground: Bool = false
    ) {
        self.page = page
        self.isSelected = isSelected
        self.width = width
        self.height = height
        self.usesGlassBackground = usesGlassBackground
    }

    var body: some View {
        selectionSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(title)
                        .font(titleFont)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if usesGlassBackground, isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(appTintColor)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: 8) {
                    Text(pageNumberTitle)
                    if let duration = page.duration {
                        Text(BiliFormatters.duration(duration))
                    }
                }
                .font(metadataFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("\(pageNumberTitle) \(title)")
        .accessibilityValue(isSelected ? "当前播放" : "")
    }

    @ViewBuilder
    private func selectionSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if usesGlassBackground {
            content()
                .background(glassFill, in: shape)
                .commentPlayerGlassRoundedRectangle(cornerRadius: 12, showsShadow: false)
                .overlay {
                    shape.strokeBorder(borderColor, lineWidth: borderWidth)
                }
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        } else {
            content()
                .background(Color(.secondarySystemGroupedBackground), in: shape)
                .overlay {
                    shape.strokeBorder(borderColor, lineWidth: borderWidth)
                }
        }
    }

    private var title: String {
        let part = page.part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return part.isEmpty ? pageNumberTitle : part
    }

    private var pageNumberTitle: String {
        "P\(page.page ?? 1)"
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.4 : 0.8
    }

    private var glassFill: Color {
        isSelected ? appTintColor.opacity(0.14) : Color(.systemBackground).opacity(0.58)
    }

    private var borderColor: Color {
        if isSelected {
            return appTintColor
        }
        return usesGlassBackground ? Color.primary.opacity(0.16) : Color(.separator).opacity(0.16)
    }

    private var titleFont: Font {
        usesGlassBackground ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var metadataFont: Font {
        usesGlassBackground ? .caption.weight(.medium) : .caption
    }

    private var horizontalPadding: CGFloat {
        usesGlassBackground ? 14 : 12
    }

    private var verticalPadding: CGFloat {
        usesGlassBackground ? 10 : 8
    }
}

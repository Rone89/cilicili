import SwiftUI

struct VideoDetailPageMenu: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var store: VideoDetailPageSelectorRenderStore
    let selectPage: (VideoPage) -> Void

    @State private var isPageSheetPresented = false

    var body: some View {
        if store.shouldShowPageSelector {
            Group {
                if libraryStore.videoDetailCompactPageSelectorExperimentEnabled {
                    VideoDetailCompactPageMenuButton(
                        pages: store.pages,
                        selectedCID: store.selectedCID,
                        showsPageSheet: $isPageSheetPresented
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
                VideoDetailPageSelectionSheet(
                    pages: store.pages,
                    coverDisplay: store.coverDisplay,
                    selectedCID: store.selectedCID,
                    selectPage: selectPage
                )
            }
        }
    }
}

/// 实验开关开启时的紧凑形态：单行显示当前分P名称和分P总数，
/// 点击后以既有弹窗查看并选择全部分P。
private struct VideoDetailCompactPageMenuButton: View {
    let pages: [VideoPage]
    let selectedCID: Int?
    @Binding var showsPageSheet: Bool

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    private var currentPage: VideoPage? {
        selectedCID.flatMap { cid in pages.first { $0.cid == cid } } ?? pages.first
    }

    var body: some View {
        Button {
            showsPageSheet = true
        } label: {
            HStack(spacing: 10) {
                Text("分P")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(compactTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text("\(pages.count) P")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "triangle.fill")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(180))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay {
                shape.strokeBorder(Color(.separator).opacity(0.16), lineWidth: 0.8)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("查看全部分P")
        .accessibilityIdentifier("video.detail.pageMenu.compact")
    }

    private var compactTitle: String {
        guard let page = currentPage else { return "" }
        let number = "P\(page.page ?? 1)"
        let part = page.part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return part.isEmpty ? number : "\(number) · \(part)"
    }

    private var accessibilityLabel: String {
        guard let page = currentPage else { return "分P" }
        let number = "P\(page.page ?? 1)"
        let part = page.part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = part.isEmpty ? "" : " \(part)"
        return "分P，当前 \(number)\(title)，共 \(pages.count) P"
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

private struct VideoDetailPageSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pages: [VideoPage]
    let coverDisplay: VideoCardDisplayModel?
    let selectedCID: Int?
    let selectPage: (VideoPage) -> Void

    @State private var isReverseOrder = false

    private var displayedPages: [VideoPage] {
        isReverseOrder ? pages.reversed() : pages
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(displayedPages) { page in
                        VideoDetailPageSheetRow(
                            page: page,
                            coverDisplay: coverDisplay,
                            isSelected: page.cid == selectedCID,
                            selectPage: selectPage
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .scrollContentBackground(.hidden)
            .background(.clear)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("video.detail.pageSheet.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            isReverseOrder.toggle()
                        }
                    } label: {
                        Image(systemName: isReverseOrder ? "arrow.down" : "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(isReverseOrder ? "正序" : "倒序")
                    .accessibilityIdentifier("video.detail.pageSheet.order")
                }
            }
        }
        .accessibilityIdentifier("video.detail.pageSheet")
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

/// 弹窗行：左侧视频封面，右侧分P信息；选中勾选用灰色而非主题色。
private struct VideoDetailPageSheetRow: View {
    @Environment(\.dismiss) private var dismiss
    let page: VideoPage
    let coverDisplay: VideoCardDisplayModel?
    let isSelected: Bool
    let selectPage: (VideoPage) -> Void

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    private static let coverSize = CGSize(width: 108, height: 61)

    var body: some View {
        Button {
            dismiss()
            guard !isSelected else { return }
            selectPage(page)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                cover
                    .frame(width: Self.coverSize.width, height: Self.coverSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                                .padding(.top, 2)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("P\(page.page ?? 1)")
                        if let duration = page.duration {
                            Text(BiliFormatters.duration(duration))
                        }
                        if isSelected {
                            Text("当前播放")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.55), in: shape)
            .overlay {
                shape.strokeBorder(Color(.separator).opacity(0.16), lineWidth: 0.8)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("P\(page.page ?? 1) \(title)")
        .accessibilityValue(isSelected ? "当前播放" : "")
    }

    @ViewBuilder
    private var cover: some View {
        if let coverDisplay {
            AdaptiveVideoCoverImage(
                display: coverDisplay,
                style: .exactCrop,
                fixedSize: Self.coverSize
            )
        } else {
            BiliMediaPlaceholder(style: .video, iconSize: 16)
        }
    }

    private var title: String {
        let part = page.part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return part.isEmpty ? "P\(page.page ?? 1)" : part
    }
}

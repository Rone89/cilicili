import SwiftUI
import UIKit

struct LiveRoomInfoBlock: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @State private var isExpanded = false

    var body: some View {
        let descriptionText = viewModel.descriptionText ?? ""
        let descriptionPreview = Self.collapsedDescriptionPreview(descriptionText)
        let hasDescriptionContent = descriptionPreview != nil
        let metadataText = metadataText(descriptionPreview: isExpanded ? nil : descriptionPreview)

        VStack(alignment: .leading, spacing: 6) {
            Text(titleText)
                .font(.callout.weight(.semibold))
                .lineSpacing(1.5)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                Text(metadataText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasDescriptionContent {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isExpanded ? "收起直播简介" : "展开直播简介")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                BiliLinkedText(
                    descriptionText,
                    font: UIFont.preferredFont(forTextStyle: .caption1),
                    textColor: .secondary
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    private var titleText: String {
        let trimmedTitle = viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "直播间" : trimmedTitle
    }

    private func metadataText(descriptionPreview: String?) -> String {
        var parts = [String]()
        let anchorName = viewModel.anchorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !anchorName.isEmpty {
            parts.append(anchorName)
        }

        if viewModel.onlineText != "在线人数 -" {
            parts.append(viewModel.onlineText)
        }

        if let areaText = viewModel.areaText {
            parts.append(areaText)
        }

        if let liveTimeText = viewModel.liveTimeText {
            parts.append(liveTimeText)
        }

        if let descriptionPreview {
            parts.append(descriptionPreview)
        }

        return parts.isEmpty ? "直播详情" : parts.joined(separator: "  ")
    }

    private static func collapsedDescriptionPreview(_ text: String) -> String? {
        let trimmed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "这个直播间暂时没有简介。" else { return nil }
        return trimmed
    }
}

struct LiveInlineMetadataButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
        .foregroundStyle(.primary)
    }
}

struct LiveRoomInfoCard: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveRoomInfoBlock(viewModel: viewModel)
            LiveRoomAnchorInfoRow(viewModel: viewModel)
            LiveRoomMetadataTagRow(
                areaText: viewModel.areaText,
                liveTimeText: viewModel.liveTimeText
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

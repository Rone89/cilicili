import SwiftUI

struct LiveStreamInlineMenu: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        if viewModel.hasMultipleStreamCandidates || viewModel.currentStreamTitle != nil {
            Menu {
                ForEach(viewModel.streamMenuItems) { item in
                    Button {
                        viewModel.selectStreamCandidate(id: item.id)
                    } label: {
                        Label(
                            item.title,
                            systemImage: item.isSelected ? "checkmark" : "antenna.radiowaves.left.and.right"
                        )
                    }
                }
            } label: {
                LiveInlineMetadataButtonLabel(
                    title: viewModel.currentStreamTitle ?? "线路",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            LiveInlineMetadataButtonLabel(
                title: "线路",
                systemImage: "antenna.radiowaves.left.and.right"
            )
            .opacity(0.45)
        }
    }
}

struct LiveQualityInlineMenu: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        if viewModel.hasMultipleQualities || viewModel.currentQualityTitle != nil {
            Menu {
                ForEach(viewModel.qualityMenuItems) { item in
                    Button {
                        viewModel.selectQuality(qn: item.qn)
                    } label: {
                        Label(
                            item.title,
                            systemImage: item.isSelected ? "checkmark" : "slider.horizontal.3"
                        )
                    }
                }
            } label: {
                LiveInlineMetadataButtonLabel(
                    title: viewModel.currentQualityTitle ?? "画质",
                    systemImage: "slider.horizontal.3"
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            LiveInlineMetadataButtonLabel(
                title: "画质",
                systemImage: "slider.horizontal.3"
            )
            .opacity(0.45)
        }
    }
}

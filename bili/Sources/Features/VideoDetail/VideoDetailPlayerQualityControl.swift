import SwiftUI

struct VideoDetailPlayerQualityControl: View {
    @Environment(\.playerNativeControlMetrics) private var controlMetrics
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onPresentationChange: (Bool) -> Void
    @State private var isShowingQualityDialog = false

    var body: some View {
        if store.hasQualityMenu {
            Button {
                isShowingQualityDialog = true
            } label: {
                Text(store.qualityAccessoryButtonTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .truncationMode(.tail)
                    .padding(.horizontal, controlMetrics.qualityHorizontalPadding)
                    .frame(maxWidth: controlMetrics.qualityButtonMaxWidth)
                    .frame(height: controlMetrics.controlHeight)
            }
            .biliPlayerCompactGlassCapsule(metrics: controlMetrics)
            .foregroundStyle(.white)
            .accessibilityLabel("清晰度")
            .sheet(isPresented: $isShowingQualityDialog) {
                VideoDetailQualitySelectionSheet(
                    store: store,
                    selectPlayVariant: selectPlayVariant
                )
            }
            .videoDetailPlayerQualityControlLifecycle(
                isShowingQualityDialog: isShowingQualityDialog,
                onPresentationChange: onPresentationChange
            )
        }
    }
}

private struct VideoDetailQualitySelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.isSwitchingPlayQuality {
                    Label("正在切换清晰度", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.qualityMenuItems) { item in
                    Button {
                        selectPlayVariant(item.variant)
                        dismiss()
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .disabled(item.isDisabled)
                }
            }
            .foregroundStyle(.primary)
            .navigationTitle("清晰度")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

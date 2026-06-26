import SwiftUI

struct VideoDetailQualityInlineButton: View {
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        if store.hasQualityMenu {
            Menu {
                if store.isSwitchingPlayQuality {
                    Button {} label: {
                        Label("正在切换清晰度", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                }

                ForEach(store.qualityMenuItems) { item in
                    Button {
                        selectPlayVariant(item.variant)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .disabled(item.isDisabled)
                }
            } label: {
                InlineMetadataButtonLabel(
                    title: store.qualityInlineButtonTitle,
                    systemImage: store.qualityButtonSystemImage
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            InlineMetadataButtonLabel(title: "清晰度", systemImage: "slider.horizontal.3")
                .opacity(0.45)
        }
    }
}

import SwiftUI

struct VideoDetailPageMenu: View {
    @ObservedObject var store: VideoDetailPageSelectorRenderStore
    let selectPage: (VideoPage) -> Void

    var body: some View {
        if store.shouldShowPageSelector {
            Menu {
                ForEach(store.pages) { page in
                    Button {
                        selectPage(page)
                    } label: {
                        Label(
                            page.part ?? "第 \(page.page ?? 1) 集",
                            systemImage: page.cid == store.selectedCID ? "checkmark" : "play.rectangle"
                        )
                    }
                }
            } label: {
                Label(store.pageCountText, systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

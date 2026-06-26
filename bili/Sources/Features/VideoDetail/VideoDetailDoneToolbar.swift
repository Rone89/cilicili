import SwiftUI

struct VideoDetailDoneToolbar: ToolbarContent {
    let finish: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("完成", action: finish)
        }
    }
}

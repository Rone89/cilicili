import SwiftUI

struct LiveRoomMetadataTagRow: View {
    let areaText: String?
    let liveTimeText: String?

    var body: some View {
        HStack(spacing: 8) {
            if let areaText {
                Label(areaText, systemImage: "tag")
            }
            if let liveTimeText {
                Label(liveTimeText, systemImage: "clock")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

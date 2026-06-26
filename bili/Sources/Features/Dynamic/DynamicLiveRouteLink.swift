import SwiftUI

struct DynamicLiveRouteLink<Label: View>: View {
    let room: LiveRoom?
    @ViewBuilder let label: () -> Label
    @State private var selectedRoom: LiveRoom?

    var body: some View {
        Button {
            selectedRoom = room
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(room == nil)
        .opacity(room == nil ? 0.72 : 1)
        .navigationDestination(item: $selectedRoom) { room in
            LiveRoomDetailView(seedRoom: room)
        }
    }
}

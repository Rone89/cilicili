import SwiftUI

private struct OpenVideoActionKey: EnvironmentKey {
    static let defaultValue: ((VideoItem) -> Void)? = nil
}

extension EnvironmentValues {
    var openVideoAction: ((VideoItem) -> Void)? {
        get { self[OpenVideoActionKey.self] }
        set { self[OpenVideoActionKey.self] = newValue }
    }
}

struct VideoRouteLink<Label: View>: View {
    let video: VideoItem
    @ViewBuilder let label: () -> Label
    @Environment(\.openVideoAction) private var openVideo

    init(_ video: VideoItem, @ViewBuilder label: @escaping () -> Label) {
        self.video = video
        self.label = label
    }

    var body: some View {
        if let openVideo {
            Button {
                openVideo(video)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: video) {
                label()
            }
        }
    }
}

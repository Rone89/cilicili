import SwiftUI

private struct OpenVideoActionKey: EnvironmentKey {
    static let defaultValue: ((VideoItem) -> Void)? = nil
}

private struct PrewarmVideoRouteActionKey: EnvironmentKey {
    static let defaultValue: ((VideoItem) -> Void)? = nil
}

extension EnvironmentValues {
    var openVideoAction: ((VideoItem) -> Void)? {
        get { self[OpenVideoActionKey.self] }
        set { self[OpenVideoActionKey.self] = newValue }
    }

    var prewarmVideoRouteAction: ((VideoItem) -> Void)? {
        get { self[PrewarmVideoRouteActionKey.self] }
        set { self[PrewarmVideoRouteActionKey.self] = newValue }
    }
}

struct VideoRouteLink<Label: View>: View {
    let video: VideoItem
    @ViewBuilder let label: () -> Label
    @Environment(\.openVideoAction) private var openVideo
    @Environment(\.prewarmVideoRouteAction) private var prewarmVideoRoute

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
            .buttonStyle(VideoRoutePrewarmButtonStyle {
                prewarmVideoRoute?(video)
            })
        } else {
            NavigationLink(value: video) {
                label()
            }
            .buttonStyle(VideoRoutePrewarmButtonStyle {
                prewarmVideoRoute?(video)
            })
        }
    }
}

private struct VideoRoutePrewarmButtonStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.94 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard isPressed else { return }
                onPress()
            }
    }
}

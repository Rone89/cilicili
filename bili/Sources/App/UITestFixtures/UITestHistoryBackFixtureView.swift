import SwiftUI

/// Network-free NavigationStack using the production toolbar and history bridge.
struct UITestHistoryBackFixtureView: View {
    @State private var path = NavigationPath()

    private var mixed: Bool { ProcessInfo.processInfo.arguments.contains("--history-mixed") }
    private var duplicate: Bool { ProcessInfo.processInfo.arguments.contains("--history-duplicate") }
    private var longTitle: String { String(repeating: "这是一个非常非常长的视频标题完整内容", count: 8) }

    var body: some View {
        NavigationStack(path: $path) {
            Button("打开") {
                if mixed { path.append(Route.searchResults) }
                else { openVideo(0) }
            }
            .accessibilityIdentifier("history.fixture.open")
            .navigationTitle(mixed ? "搜索" : "首页")
            .navigationHistoryTitle(mixed ? "搜索" : "首页")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .searchResults:
                    Button("打开 UP 主空间") { path.append(Route.owner) }
                        .accessibilityIdentifier("history.fixture.owner")
                        .navigationTitle("搜索结果")
                        .navigationHistoryTitle("搜索结果")
                case .owner:
                    Button("打开视频") { openVideo(0) }
                        .accessibilityIdentifier("history.fixture.video")
                        .navigationTitle("某 UP 主空间")
                        .navigationHistoryTitle("某 UP 主空间")
                case .video(let index, let title):
                    VideoPage(index: index, title: title) { openVideo(index + 1) }
                        .navigationHistoryTitle(title)
                }
            }
        }
        .navigationHistoryStack(path: $path, rootTitle: mixed ? "搜索" : "首页")
    }

    private func openVideo(_ index: Int) {
        let title: String
        if index == 0, ProcessInfo.processInfo.arguments.contains("--history-long-title") { title = longTitle }
        else { title = duplicate && index < 2 ? "同名视频" : "Video \(String(UnicodeScalar(65 + index)!))" }
        path.append(Route.video(index, title))
    }

    private enum Route: Hashable {
        case searchResults
        case owner
        case video(Int, String)
    }

    private struct VideoPage: View {
        let index: Int
        let title: String
        let onNext: () -> Void
        @State private var instanceID = UUID()
        @State private var selection = VideoDetailContentTab.detail

        var body: some View {
            VStack {
                Text(title).accessibilityIdentifier("history.fixture.title")
                Text(instanceID.uuidString).accessibilityIdentifier("history.fixture.instance")
                Text(selection.rawValue).accessibilityIdentifier("history.fixture.selection")
                Button("下一个视频", action: onNext).accessibilityIdentifier("history.fixture.next")
                VideoDetailNativeContentTabView(
                    selection: $selection, layoutWidth: 390, topInset: 0,
                    mountsSecondaryContent: true, onScrollOffsetChange: nil,
                    content: { tab, _ in Text(tab.title) }
                )
            }
            // Match video pages whose navigation bar doesn't supply a title.
        }
    }
}

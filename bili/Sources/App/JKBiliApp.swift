import SwiftUI
import UIKit

@main
@MainActor
struct JKBiliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 96 * 1024 * 1024,
            diskCapacity: 768 * 1024 * 1024
        )
        RefreshRateManager.shared.restorePersistedPreference()
    }

    var body: some Scene {
        WindowGroup {
            MainInterfaceHost()
                .background(LaunchWindowBackgroundInstaller())
        }
    }

}

private struct LaunchWindowBackgroundInstaller: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            LaunchAppearance.apply(to: view.window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        DispatchQueue.main.async {
            LaunchAppearance.apply(to: uiView.window)
        }
    }
}

private struct MainInterfaceHost: View {
    @StateObject private var dependencies = AppDependencies()

    var body: some View {
        RootTabView()
            .scrollIndicators(.hidden, axes: .vertical)
            .environmentObject(dependencies)
            .environmentObject(dependencies.sessionStore)
            .environmentObject(dependencies.libraryStore)
            .environmentObject(dependencies.homeRecommendDiagnosticsStore)
    }
}

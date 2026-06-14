import SwiftUI
import UIKit

@main
@MainActor
struct JKBiliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var showsSplash = true
    @State private var loadsMainInterface = false

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 96 * 1024 * 1024,
            diskCapacity: 768 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.ciliciliLaunchSplashBackground
                    .ignoresSafeArea()

                if loadsMainInterface {
                    MainInterfaceHost()
                        .transition(.opacity)
                }

                if showsSplash {
                    AppSplashView()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .background(LaunchWindowBackgroundInstaller())
            .task {
                guard showsSplash else { return }
                try? await Task.sleep(nanoseconds: 120_000_000)
                loadsMainInterface = true
                try? await Task.sleep(nanoseconds: 820_000_000)
                withAnimation(.smooth(duration: 0.30)) {
                    showsSplash = false
                }
            }
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
    }
}

private struct AppSplashView: View {
    var body: some View {
        Color.ciliciliLaunchSplashBackground
            .ignoresSafeArea()
            .overlay {
                Image(uiImage: LaunchSplashImageProvider.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .accessibilityHidden(true)
            }
        .ignoresSafeArea()
        .accessibilityLabel("cilicili")
    }
}

private enum LaunchSplashImageProvider {
    static let image: UIImage = {
        let bundle = Bundle.main
        let candidates = [
            "CiliciliLaunchScreenLogo@3x",
            "CiliciliLaunchScreenLogo@2x",
            "CiliciliLaunchScreenLogo"
        ]

        for name in candidates {
            if let path = bundle.path(forResource: name, ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }

        if let image = UIImage(named: "CiliciliLaunchScreenLogo", in: bundle, compatibleWith: nil) {
            return image
        }

        return UIImage()
    }()
}

private extension Color {
    static let ciliciliLaunchSplashBackground = Color(uiColor: LaunchAppearance.backgroundColor)
}

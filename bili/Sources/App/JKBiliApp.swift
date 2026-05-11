import SwiftUI
import UIKit

@main
@MainActor
struct JKBiliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dependencies = AppDependencies()

    init() {
        AppNavigationChrome.configureGlobalAppearance()
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dependencies)
                .environmentObject(dependencies.sessionStore)
                .environmentObject(dependencies.libraryStore)
        }
    }

}

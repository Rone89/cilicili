import SwiftUI
import UIKit

@main
@MainActor
struct JKBiliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dependencies = AppDependencies()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 96 * 1024 * 1024,
            diskCapacity: 768 * 1024 * 1024
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

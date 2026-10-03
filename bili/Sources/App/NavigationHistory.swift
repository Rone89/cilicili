import Combine
import SwiftUI
import UIKit

struct NavigationHistoryEntry: Identifiable, Equatable {
    let id: ObjectIdentifier
    /// Root is depth zero; a destination's depth is its retained path length.
    let depth: Int
    let title: String
}

/// NavigationPath stays the source of truth. This only reads the public controller
/// stack because a type-erased NavigationPath cannot enumerate its route values.
@MainActor
final class NavigationHistoryController: ObservableObject {
    @Published private(set) var entries: [NavigationHistoryEntry] = []
    weak var navigationController: UINavigationController?
    private var titles: [ObjectIdentifier: String] = [:]
    private(set) var isEnabled = true

    func register(title: String, controller: UIViewController, in navigation: UINavigationController) {
        guard isEnabled, navigationController == nil || navigationController === navigation else { return }
        navigationController = navigation
        titles[ObjectIdentifier(controller)] = title
    }

    func refresh(pathDepth: Int, rootTitle: String) {
        guard isEnabled, let controllers = navigationController?.viewControllers,
              controllers.count == pathDepth + 1 else {
            if !entries.isEmpty { entries = [] }
            return
        }
        let liveIDs = Set(controllers.map(ObjectIdentifier.init))
        titles = titles.filter { liveIDs.contains($0.key) }
        let history = controllers.dropLast().enumerated().reversed().map { depth, controller in
            NavigationHistoryEntry(
                id: ObjectIdentifier(controller), depth: depth,
                title: depth == 0 ? rootTitle : titles[ObjectIdentifier(controller)] ?? Self.pageTitle(in: controller)
                    ?? controller.navigationItem.title ?? controller.title ?? "页面"
            )
        }
        if entries != history { entries = history }
    }

    private static func pageTitle(in controller: UIViewController) -> String? {
        // A retained page already owns its route title. Read that metadata even
        // when the experiment was enabled after this page became covered.
        var children = controller.children
        while let child = children.first {
            children.removeFirst()
            if let probe = child as? NavigationHistoryTitleProbe.Controller { return probe.historyTitle }
            children.append(contentsOf: child.children)
        }
        return nil
    }

    func removalCount(to entry: NavigationHistoryEntry, pathDepth: Int) -> Int? {
        guard isEnabled, let navigationController, navigationController.transitionCoordinator == nil,
              navigationController.viewControllers.count == pathDepth + 1,
              entry.depth >= 0, entry.depth < pathDepth,
              ObjectIdentifier(navigationController.viewControllers[entry.depth]) == entry.id
        else { return nil }
        return pathDepth - entry.depth
    }

    func reset() {
        isEnabled = false
        entries = []
        titles = [:]
        navigationController = nil
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { isEnabled = true }
        else { reset() }
    }
}

struct NavigationHistoryContext {
    let controller: NavigationHistoryController
    let path: Binding<NavigationPath>
    let rootTitle: String

    func refresh() {
        controller.refresh(pathDepth: path.wrappedValue.count, rootTitle: rootTitle)
    }

    func pop(to entry: NavigationHistoryEntry) {
        guard let count = controller.removalCount(to: entry, pathDepth: path.wrappedValue.count) else { return }
        path.wrappedValue.removeLast(count)
    }

    func popOne() {
        guard controller.isEnabled, !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }
}

private struct NavigationHistoryContextKey: EnvironmentKey {
    static let defaultValue: NavigationHistoryContext? = nil
}

private struct NavigationHistoryBackActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var navigationHistoryBackAction: (() -> Void)? {
        get { self[NavigationHistoryBackActionKey.self] }
        set { self[NavigationHistoryBackActionKey.self] = newValue }
    }

    var navigationHistoryContext: NavigationHistoryContext? {
        get { self[NavigationHistoryContextKey.self] }
        set { self[NavigationHistoryContextKey.self] = newValue }
    }
}

extension View {
    func navigationHistoryStack(path: Binding<NavigationPath>, rootTitle: String, enabled: Bool) -> some View {
        modifier(NavigationHistoryStackModifier(path: path, rootTitle: rootTitle, enabled: enabled))
    }

    func navigationHistoryTitle(_ title: String) -> some View {
        modifier(NavigationHistoryTitleModifier(title: title))
    }
}

private struct NavigationHistoryStackModifier: ViewModifier {
    let path: Binding<NavigationPath>
    let rootTitle: String
    let enabled: Bool
    @StateObject private var controller = NavigationHistoryController()

    func body(content: Content) -> some View {
        content
            .environment(\.navigationHistoryContext, enabled
                ? NavigationHistoryContext(controller: controller, path: path, rootTitle: rootTitle) : nil)
            .onChange(of: path.wrappedValue.count) { _, _ in
                guard enabled else { return }
                controller.refresh(pathDepth: path.wrappedValue.count, rootTitle: rootTitle)
            }
            .onChange(of: enabled) { _, isEnabled in
                controller.setEnabled(isEnabled)
            }
            .onAppear { controller.setEnabled(enabled) }
    }
}

private struct NavigationHistoryTitleModifier: ViewModifier {
    let title: String
    @Environment(\.navigationHistoryContext) private var history

    func body(content: Content) -> some View {
        content.background {
            // Title metadata belongs to the existing page, not to a shadow route
            // stack. Without an enabled context this probe performs no work.
            NavigationHistoryTitleProbe(title: title, history: history)
                .allowsHitTesting(false)
        }
    }
}

/// Reads public parent/controller relationships; never changes controllers,
/// navigation items, navigation delegates, or interactive-pop recognizers.
private struct NavigationHistoryTitleProbe: UIViewControllerRepresentable {
    let title: String
    let history: NavigationHistoryContext?

    func makeUIViewController(context: Context) -> Controller {
        Controller(title: title, history: history)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.historyTitle = title
        controller.history = history
        controller.scheduleRefresh()
    }

    final class Controller: UIViewController {
        var historyTitle: String
        var history: NavigationHistoryContext?

        init(title: String, history: NavigationHistoryContext?) {
            historyTitle = title
            self.history = history
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() { view = ClearPassthroughView() }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            scheduleRefresh()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            refresh()
        }

        func scheduleRefresh() {
            guard history != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        private func refresh() {
            guard let history, history.controller.isEnabled, let navigation = navigationController else { return }
            var ancestor = parent
            while let controller = ancestor {
                if navigation.viewControllers.contains(where: { $0 === controller }) {
                    history.controller.register(title: historyTitle, controller: controller, in: navigation)
                    history.refresh()
                    return
                }
                ancestor = controller.parent
            }
        }
    }
}

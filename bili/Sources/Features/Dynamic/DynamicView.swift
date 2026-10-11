import SwiftUI

struct DynamicView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        DynamicContentRoot(
            api: dependencies.api,
            libraryStore: libraryStore,
            sessionStore: dependencies.sessionStore
        )
    }
}

private struct DynamicContentRoot: View {
    @Environment(\.rootNavigationTitleHidden) private var rootNavigationTitleHidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let api: BiliAPIClient
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var holder: DynamicViewModelHolder
    @State private var selectedFeed: DynamicFeedKind = .all
    @State private var hidesNavigationChrome = false

    init(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        self.api = api
        self.libraryStore = libraryStore
        self.sessionStore = sessionStore
        _holder = StateObject(
            wrappedValue: DynamicViewModelHolder(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore
            )
        )
    }

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                DynamicFeedScreenContent(
                    api: api,
                    viewModel: viewModel,
                    topUploaderStripViewModel: holder.topUploaderStripViewModel ?? viewModel,
                    isLoggedIn: sessionStore.isLoggedIn
                )
            } else {
                DynamicInitialFeedContent(isLoggedIn: sessionStore.isLoggedIn)
            }
        }
        .environment(\.rootNavigationTitleHidden, navigationChromeVisibility)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("动态内容", selection: $selectedFeed) {
                    ForEach(DynamicFeedKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .accessibilityIdentifier("dynamic.feedPicker")
                .opacity(hidesNavigationChrome ? 0 : 1)
                .disabled(hidesNavigationChrome)
                .accessibilityHidden(hidesNavigationChrome)
                .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: hidesNavigationChrome)
            }
            .sharedBackgroundVisibility(hidesNavigationChrome ? .hidden : .automatic)
        }
        .onChange(of: selectedFeed) { _, kind in
            holder.selectFeed(kind, api: api, libraryStore: libraryStore, sessionStore: sessionStore)
        }
        .onChange(of: DynamicFeedAccountContext(
            mainCredentialVersion: sessionStore.playbackCredentialVersion,
            dynamicFeedCredentialVersion: sessionStore.dynamicFeedAccountCredentialVersion,
            multiAccountEnabled: libraryStore.multiAccountEnabled
        )) { _, _ in
            selectedFeed = .all
            holder.reconfigure(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore
            )
        }
    }

    private var navigationChromeVisibility: Binding<Bool> {
        Binding(
            get: { hidesNavigationChrome },
            set: { isHidden in
                // Keep a local signal for dynamic pages pushed from Home, where
                // the root title binding intentionally ignores destination scrolls.
                hidesNavigationChrome = isHidden
                rootNavigationTitleHidden.wrappedValue = isHidden
            }
        )
    }
}

private struct DynamicFeedAccountContext: Equatable {
    let mainCredentialVersion: Int
    let dynamicFeedCredentialVersion: Int
    let multiAccountEnabled: Bool
}

extension View {
    @ViewBuilder
    func dynamicLoadMoreTask<ID: Equatable>(
        if condition: Bool,
        id: ID,
        action: @escaping () async -> Void
    ) -> some View {
        if condition {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}

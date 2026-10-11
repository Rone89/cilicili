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
    let api: BiliAPIClient
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var holder: DynamicViewModelHolder
    @State private var selectedFeed: DynamicFeedKind = .all

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
                    isLoggedIn: sessionStore.isLoggedIn
                )
            } else {
                DynamicInitialFeedContent(isLoggedIn: sessionStore.isLoggedIn)
            }
        }
        .toolbar {
            if libraryStore.dynamicVideoFilterExperimentEnabled {
                ToolbarItem(placement: .principal) {
                    Picker("动态内容", selection: $selectedFeed) {
                        ForEach(DynamicFeedKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .accessibilityIdentifier("dynamic.feedPicker")
                }
            }
        }
        .onChange(of: selectedFeed) { _, kind in
            holder.selectFeed(kind, api: api, libraryStore: libraryStore, sessionStore: sessionStore)
        }
        .onChange(of: libraryStore.dynamicVideoFilterExperimentEnabled) { _, enabled in
            if !enabled { selectedFeed = .all }
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

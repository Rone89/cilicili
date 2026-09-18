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
        .onChange(of: DynamicFeedAccountContext(
            mainCredentialVersion: sessionStore.playbackCredentialVersion,
            dynamicFeedCredentialVersion: sessionStore.dynamicFeedAccountCredentialVersion
        )) { _, _ in
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

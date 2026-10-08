import SwiftUI

struct VideoDetailWatchLaterButton: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let aid: Int?
    @State private var isAdded: Bool?
    @State private var isBusy = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var context: LibraryManagementContext?

    var body: some View {
        Button {
            guard let aid, !isBusy, !isLoading else { return }
            guard let context, let isAdded else { Task { await load(reportError: true) }; return }
            isBusy = true
            Task {
                do {
                    try await dependencies.api.setWatchLater(aid: aid, added: !isAdded, context: context)
                    guard await dependencies.api.isCurrentLibraryContext(context) else { throw CancellationError() }
                    self.isAdded = !isAdded
                } catch { self.error = error.localizedDescription }
                isBusy = false
            }
        } label: {
            Label(isAdded == nil ? "读取稍后再看状态" : (isAdded == true ? "移除稍后再看" : "添加稍后再看"), systemImage: isAdded == true ? "clock.badge.checkmark" : "clock.badge.plus")
        }
        .buttonStyle(.bordered)
        .disabled(isBusy || isLoading || aid == nil)
        .task(id: "\(aid ?? 0)-\(sessionStore.accountConfigurationVersion)-\(sessionStore.historyAccountCredentialVersion)-\(sessionStore.playbackCredentialVersion)-\(libraryStore.accountWatchLaterChangeRevision)") {
            if isBusy || isLoading {
                while isBusy || isLoading { try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { return } }
            }
            await load(reportError: false)
        }
        .alert("稍后再看", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func load(reportError: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        context = nil; isAdded = nil
        do {
            let context = try await dependencies.api.libraryManagementContext(purpose: .historyRead)
            let entries = try await dependencies.api.fetchAccountWatchLater()
            guard !Task.isCancelled, await dependencies.api.isCurrentLibraryContext(context) else { return }
            self.context = context
            isAdded = entries.contains { $0.aid == aid }
        } catch { if reportError { self.error = error.localizedDescription } }
    }

}

import SwiftUI

struct VideoDetailMoreMenu: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let api: BiliAPIClient
    let aid: Int?
    let onComment: () -> Void
    let onRefresh: () -> Void

    @State private var isAdded: Bool?
    @State private var isBusy = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var context: LibraryManagementContext?
    @State private var loadedIdentity: String?
    @State private var completedMessage: String?

    var body: some View {
        Menu {
            if libraryStore.accountLibraryManagementExperimentEnabled {
                Section {
                    Button(action: performWatchLaterAction) {
                        Label(watchLaterTitle, systemImage: isAdded == true ? "clock.badge.checkmark" : "clock.badge.plus")
                    }
                    .disabled(isBusy || isLoading || aid == nil || !sessionStore.isLoggedIn)
                    .accessibilityIdentifier("video.detail.watchLater")
                }
                Section { commentActions }
            } else {
                commentActions
            }
        } label: {
            Image(systemName: completedMessage == nil ? "ellipsis" : "checkmark")
                .frame(width: 38, height: 38)
        }
        .tint(.primary)
        .accessibilityLabel(libraryStore.accountLibraryManagementExperimentEnabled ? "更多视频操作" : "更多评论操作")
        .accessibilityValue(completedMessage ?? "")
        .accessibilityIdentifier("video.detail.toolbar-comment-more")
        .task(id: "\(identity)-\(libraryStore.accountWatchLaterChangeRevision)") {
            while isBusy || isLoading {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await load(reportError: false)
        }
        .task(id: completedMessage) {
            guard completedMessage != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            completedMessage = nil
        }
        .alert("稍后再看", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var commentActions: some View {
        Group {
            Button(action: onComment) { Label("评论", systemImage: "square.and.pencil") }
            Button(action: onRefresh) { Label("刷新评论区", systemImage: "arrow.clockwise") }
        }
    }

    private var identity: String {
        "\(aid ?? 0)-\(sessionStore.accountConfigurationVersion)-\(sessionStore.historyAccountCredentialVersion)-\(sessionStore.playbackCredentialVersion)-\(libraryStore.accountLibraryManagementExperimentEnabled)"
    }

    private var watchLaterTitle: String {
        if !sessionStore.isLoggedIn { return "登录后使用稍后再看" }
        if isBusy { return "正在更新稍后再看…" }
        if isLoading { return "稍后再看" }
        guard loadedIdentity == identity, let isAdded else { return "重新读取稍后再看状态" }
        return isAdded ? "从稍后再看移除" : "添加到稍后再看"
    }

    private func performWatchLaterAction() {
        guard libraryStore.accountLibraryManagementExperimentEnabled, let aid, !isBusy, !isLoading else { return }
        guard loadedIdentity == identity, let context, let isAdded else {
            Task { await load(reportError: true) }
            return
        }
        let operationIdentity = identity
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await api.setWatchLater(aid: aid, added: !isAdded, context: context)
                guard operationIdentity == identity, await api.isCurrentLibraryContext(context) else { return }
                self.isAdded = !isAdded
                completedMessage = isAdded ? "已从稍后再看移除" : "已添加到稍后再看"
                Haptics.success()
            } catch {
                guard operationIdentity == identity else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func load(reportError: Bool) async {
        context = nil; isAdded = nil; loadedIdentity = nil
        guard libraryStore.accountLibraryManagementExperimentEnabled, sessionStore.isLoggedIn, aid != nil, !isLoading else { return }
        let readIdentity = identity
        isLoading = true
        defer { isLoading = false }
        do {
            let context = try await api.libraryManagementContext(purpose: .historyRead)
            let entries = try await api.fetchAccountWatchLater()
            guard !Task.isCancelled, readIdentity == identity, await api.isCurrentLibraryContext(context) else { return }
            self.context = context
            isAdded = entries.contains { $0.aid == aid }
            loadedIdentity = readIdentity
        } catch {
            if reportError, readIdentity == identity { self.error = error.localizedDescription }
        }
    }
}

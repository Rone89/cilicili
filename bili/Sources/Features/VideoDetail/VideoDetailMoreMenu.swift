import SwiftUI
import UIKit

struct VideoDetailMoreMenu: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let api: BiliAPIClient
    let aid: Int?
    let shareURL: URL?
    let shareSubject: String
    let shareMessage: String
    var usesPlainStyle = false

    @State private var isAdded: Bool?
    @State private var isBusy = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var context: LibraryManagementContext?
    @State private var loadedIdentity: String?
    @State private var completedMessage: String?

    var body: some View {
        Menu {
            Section {
                Button(action: performWatchLaterAction) {
                    Label(watchLaterTitle, systemImage: isAdded == true ? "clock.badge.checkmark" : "clock.badge.plus")
                }
                .disabled(isBusy || isLoading || aid == nil || !sessionStore.isLoggedIn)
                .accessibilityIdentifier("video.detail.watchLater")
            }
            Section { linkActions }
        } label: {
            VideoDetailActionStripIconLabel(
                systemImage: completedMessage == nil ? "ellipsis" : "checkmark",
                foregroundStyle: usesPlainStyle ? .secondary : .primary
            )
        }
        .videoDetailActionStripButtonAppearance(usesPlainStyle: usesPlainStyle, tint: usesPlainStyle ? .secondary : nil)
        .menuIndicator(.hidden)
        .accessibilityLabel("更多视频操作")
        .accessibilityValue(completedMessage ?? "")
        .accessibilityIdentifier("video.detail.more")
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

    private var linkActions: some View {
        Group {
            Button {
                guard let shareURL else { return }
                UIPasteboard.general.string = shareURL.absoluteString
                completedMessage = "已复制链接"
                Haptics.success()
            } label: { Label("复制链接", systemImage: "link") }
            .disabled(shareURL == nil)
            .accessibilityIdentifier("video.detail.more.copyLink")

            if let shareURL {
                ShareLink(item: shareURL, subject: Text(shareSubject), message: Text(shareMessage)) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("video.detail.more.share")
            } else {
                Button("分享", systemImage: "square.and.arrow.up") {}
                    .disabled(true)
            }
        }
    }

    private var identity: String {
        "\(aid ?? 0)-\(sessionStore.accountConfigurationVersion)-\(sessionStore.historyAccountCredentialVersion)-\(sessionStore.playbackCredentialVersion)"
    }

    private var watchLaterTitle: String {
        if !sessionStore.isLoggedIn { return "登录后使用稍后再看" }
        if isBusy { return "正在更新稍后再看…" }
        if isLoading { return "稍后再看" }
        guard loadedIdentity == identity, let isAdded else { return "重新读取稍后再看状态" }
        return isAdded ? "从稍后再看移除" : "添加到稍后再看"
    }

    private func performWatchLaterAction() {
        guard let aid, !isBusy, !isLoading else { return }
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
        guard sessionStore.isLoggedIn, aid != nil, !isLoading else { return }
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

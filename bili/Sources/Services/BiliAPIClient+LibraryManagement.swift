import Foundation

nonisolated struct LibraryManagementContext: Sendable {
    let purpose: BiliAccountPurpose
    let snapshot: BiliAPIClient.RequestSnapshot
}

extension BiliAPIClient {
    nonisolated func libraryManagementContext(purpose: BiliAccountPurpose) async throws -> LibraryManagementContext {
        let snapshot = await requestSnapshot(purpose: purpose)
        guard snapshot.isLoggedIn, snapshot.currentUserMID != nil else { throw BiliAPIError.missingSESSDATA }
        guard snapshot.csrfToken?.isEmpty == false else { throw BiliAPIError.missingCSRF }
        return LibraryManagementContext(purpose: purpose, snapshot: snapshot)
    }

    nonisolated func isCurrentLibraryContext(_ context: LibraryManagementContext) async -> Bool {
        let current = await requestSnapshot(purpose: context.purpose)
        return current.isLoggedIn && current.currentUserMID == context.snapshot.currentUserMID
            && current.playbackCredentialVersion == context.snapshot.playbackCredentialVersion
            && current.cookieHeader == context.snapshot.cookieHeader
    }

    nonisolated func libraryManagementPost(path: String, fields: [String: String], context: LibraryManagementContext) async throws {
        guard await isCurrentLibraryContext(context) else { throw CancellationError() }
        var body = fields
        body["csrf"] = context.snapshot.csrfToken
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL, path: path, body: body, cookieHeader: context.snapshot.cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard await isCurrentLibraryContext(context) else { throw CancellationError() }
        await MainActor.run { libraryStore.recordAccountLibraryChange(purpose: context.purpose) }
    }

    nonisolated func changeFavoriteResources(aids: [Int], addFolderID: Int? = nil, removeFolderID: Int? = nil,
                                 context: LibraryManagementContext) async throws {
        guard context.purpose == .interaction, !aids.isEmpty, aids.allSatisfy({ $0 > 0 }), addFolderID != removeFolderID,
              addFolderID.map({ $0 > 0 }) ?? true, removeFolderID.map({ $0 > 0 }) ?? true
        else { throw BiliAPIError.missingPayload }
        try await libraryManagementPost(path: "/x/v3/fav/resource/batch-deal", fields: [
            "resources": aids.map { "\($0):2" }.joined(separator: ","),
            "add_media_ids": addFolderID.map(String.init) ?? "",
            "del_media_ids": removeFolderID.map(String.init) ?? "",
        ], context: context)
    }

    nonisolated func removeWatchLater(aids: [Int], context: LibraryManagementContext) async throws {
        guard context.purpose == .historyRead, !aids.isEmpty, aids.allSatisfy({ $0 > 0 }) else { throw BiliAPIError.missingPayload }
        try await libraryManagementPost(path: "/x/v2/history/toview/v2/dels",
            fields: ["resources": aids.map(String.init).joined(separator: ",")], context: context)
    }

    nonisolated func setWatchLater(aid: Int, added: Bool, context: LibraryManagementContext) async throws {
        guard aid > 0 else { throw BiliAPIError.missingPayload }
        if added {
            try await libraryManagementPost(path: "/x/v2/history/toview/add", fields: ["aid": String(aid)], context: context)
        } else {
            try await removeWatchLater(aids: [aid], context: context)
        }
    }

    nonisolated func clearWatchLater(context: LibraryManagementContext) async throws {
        try await libraryManagementPost(path: "/x/v2/history/toview/clear", fields: [:], context: context)
    }

    nonisolated func fetchManagedFavoriteFolder(id: Int, context: LibraryManagementContext) async throws -> FavoriteFolder {
        guard await isCurrentLibraryContext(context) else { throw CancellationError() }
        let response: BiliResponse<FavoriteFolder> = try await get(base: baseURL, path: "/x/v3/fav/folder/info",
            query: ["media_id": String(id)], cookieHeader: context.snapshot.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard await isCurrentLibraryContext(context), let folder = response.payload else { throw CancellationError() }
        return folder
    }

    nonisolated func saveFavoriteFolder(folder: FavoriteFolder?, title: String, intro: String, isPrivate: Bool,
                            context: LibraryManagementContext) async throws {
        if let folder, (!folder.canManage(accountMID: context.snapshot.currentUserMID) || folder.isDefaultFolder) {
            throw BiliAPIError.api(code: -400, message: "该收藏夹不能编辑")
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw BiliAPIError.api(code: -400, message: "请输入收藏夹名称") }
        var fields = ["title": title, "intro": intro, "privacy": isPrivate ? "1" : "0", "cover": folder?.cover ?? ""]
        if let folder { fields["media_id"] = String(folder.id) }
        try await libraryManagementPost(path: folder == nil ? "/x/v3/fav/folder/add" : "/x/v3/fav/folder/edit",
                                        fields: fields, context: context)
    }

    nonisolated func deleteFavoriteFolder(_ folder: FavoriteFolder, context: LibraryManagementContext) async throws {
        guard folder.canManage(accountMID: context.snapshot.currentUserMID), !folder.isDefaultFolder else {
            throw BiliAPIError.api(code: -400, message: "该收藏夹不能删除")
        }
        try await libraryManagementPost(path: "/x/v3/fav/folder/del", fields: ["media_ids": String(folder.id), "platform": "web"], context: context)
    }

    nonisolated func sortFavoriteFolders(ids: [Int], context: LibraryManagementContext) async throws {
        let fields = BiliAppSigner.sign(["sort": ids.map(String.init).joined(separator: ","),
                                        "csrf": context.snapshot.csrfToken ?? ""], profile: .androidLogin)
        try await libraryManagementPost(path: "/x/v3/fav/folder/sort", fields: fields, context: context)
    }
}

import Foundation

extension BiliAPIClient {
    func fetchComments(aid: Int, cursor: String = "", sort: CommentSort = .hot) async throws -> CommentPage {
        try await fetchComments(oid: String(aid), type: 1, cursor: cursor, sort: sort)
    }

    func fetchComments(oid: String, type: Int, cursor: String = "", sort: CommentSort = .hot) async throws
        -> CommentPage
    {
        let mode = sort == .hot ? "3" : "2"
        let pagination = try Self.commentPaginationString(offset: cursor)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/main",
            query: [
                "oid": oid,
                "type": String(type),
                "mode": mode,
                "plat": "1",
                "pagination_str": pagination,
            ],
            priority: URLSessionTask.defaultPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    private static func commentPaginationString(offset: String) throws -> String {
        let data = try JSONEncoder().encode(CommentPaginationRequest(offset: offset))
        return String(decoding: data, as: UTF8.self)
    }

    func fetchCommentReplies(
        aid: Int,
        root: Int,
        page: Int = 1,
        sort: CommentSort? = nil
    ) async throws -> CommentPage {
        try await fetchCommentReplies(oid: String(aid), type: 1, root: root, page: page, sort: sort)
    }

    func fetchCommentReplies(
        oid: String,
        type: Int,
        root: Int,
        page: Int = 1,
        sort: CommentSort? = nil
    ) async throws -> CommentPage {
        var query = [
            "oid": oid,
            "type": String(type),
            "root": String(root),
            "pn": String(page),
            "ps": "20",
        ]
        if sort == .time {
            query["sort"] = "1"
        }
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/reply",
            query: query,
            priority: URLSessionTask.lowPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    func fetchCommentDialog(aid: Int, root: Int, dialog: Int, size: Int = 20) async throws -> CommentPage {
        try await fetchCommentDialog(oid: String(aid), type: 1, root: root, dialog: dialog, size: size)
    }

    func fetchCommentDialog(oid: String, type: Int, root: Int, dialog: Int, size: Int = 20) async throws -> CommentPage
    {
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/dialog/cursor",
            query: [
                "oid": oid,
                "type": String(type),
                "root": String(root),
                "dialog": String(dialog),
                "size": String(size),
            ],
            priority: URLSessionTask.lowPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }
}

nonisolated enum CommentSort: CaseIterable, Identifiable, Hashable {
    case hot
    case time

    var id: Self { self }

    var title: String {
        switch self {
        case .hot:
            return "最热"
        case .time:
            return "最新"
        }
    }
}

nonisolated private struct CommentPaginationRequest: Encodable {
    let offset: String
}

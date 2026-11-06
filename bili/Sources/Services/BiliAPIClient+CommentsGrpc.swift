import Foundation

/// 评论分页 gRPC 通道（PiliPlus 同款）。
///
/// 网页版 `/x/v2/reply/main` 对短时连续翻页风控严格（-352 高发）；App 侧
/// `bilibili.main.community.reply.v1.Reply/MainList` 走 gRPC 通道，不受该网页
/// 限流约束。报文按 PiliPlus 生成的 proto 字段号手写编解码（复用听视频功能的
/// `BiliProtoWriter/Reader` 基建），解码结果映射回现有 `CommentPage` 的 JSON
/// 结构，UI 层完全不用改。任何失败由调用方回退网页接口。
nonisolated enum BiliReplyMainListCodec {
    static let endpointPath = "/bilibili.main.community.reply.v1.Reply/MainList"
    static let pageSize = 20

    enum CodecError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "评论 gRPC 接口返回了无法识别的数据"
            }
        }
    }

    // MARK: 请求

    /// MainListReq: 1 oid, 2 type, 9 mode(2=time 3=hot), 10 pagination(FeedPagination)
    static func encodeRequest(
        oid: Int,
        type: Int,
        sort: CommentSort,
        offset: String?
    ) -> Data {
        var request = BiliProtoWriter()
        request.appendVarint(field: 1, value: UInt64(max(oid, 0)))
        request.appendVarint(field: 2, value: UInt64(max(type, 0)))
        request.appendVarint(field: 9, value: sort == .time ? 2 : 3)
        request.appendMessage(field: 10) { pagination in
            pagination.appendVarint(field: 1, value: UInt64(pageSize))
            let normalizedOffset = offset?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !normalizedOffset.isEmpty {
                pagination.appendString(field: 2, value: normalizedOffset)
            }
        }
        return request.data
    }

    // MARK: 响应

    /// MainListReply: 1 CursorReply, 2 replies, 3 SubjectControl, 4 upTop,
    /// 5 adminTop, 6 voteTop, 14 topReplies, 20 FeedPaginationReply。
    /// 解码成现有 `CommentPage` 的 JSON 结构后走原有 Decodable，
    /// 保证 UI 层行为与网页接口完全一致。
    static func decodePage(_ data: Data) throws -> CommentPage {
        var reader = BiliProtoReader(data: data)
        var replyDicts: [[String: Any]] = []
        var topDicts: [[String: Any]] = []
        var cursorNext = ""
        var cursorIsEnd = false
        var totalCount: Int64 = -1
        var nextOffset = ""

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .lengthDelimited):
                var cursor = BiliProtoReader(bytes: try reader.readLengthDelimited())
                while !cursor.isAtEnd {
                    let cursorKey = try cursor.readKey()
                    switch (cursorKey.field, cursorKey.wire) {
                    case (1, .lengthDelimited):
                        cursorNext = try cursor.readString()
                    case (4, .varint):
                        cursorIsEnd = try cursor.readVarint() != 0
                    default:
                        try cursor.skipField(wire: cursorKey.wire)
                    }
                }
            case (2, .lengthDelimited):
                replyDicts.append(try decodeReply(reader.readLengthDelimited()))
            case (3, .lengthDelimited):
                var subject = BiliProtoReader(bytes: try reader.readLengthDelimited())
                while !subject.isAtEnd {
                    let subjectKey = try subject.readKey()
                    switch (subjectKey.field, subjectKey.wire) {
                    case (16, .varint):
                        totalCount = Int64(bitPattern: try subject.readVarint())
                    default:
                        try subject.skipField(wire: subjectKey.wire)
                    }
                }
            case (4, .lengthDelimited):
                topDicts.append(try decodeReply(reader.readLengthDelimited()))
            case (5, .lengthDelimited):
                topDicts.append(try decodeReply(reader.readLengthDelimited()))
            case (6, .lengthDelimited):
                topDicts.append(try decodeReply(reader.readLengthDelimited()))
            case (14, .lengthDelimited):
                topDicts.append(try decodeReply(reader.readLengthDelimited()))
            case (20, .lengthDelimited):
                var pagination = BiliProtoReader(bytes: try reader.readLengthDelimited())
                while !pagination.isAtEnd {
                    let paginationKey = try pagination.readKey()
                    switch (paginationKey.field, paginationKey.wire) {
                    case (1, .lengthDelimited):
                        nextOffset = try pagination.readString()
                    default:
                        try pagination.skipField(wire: paginationKey.wire)
                    }
                }
            default:
                try reader.skipField(wire: key.wire)
            }
        }

        var cursor: [String: Any] = ["is_end": cursorIsEnd]
        if !cursorNext.isEmpty { cursor["next"] = cursorNext }
        if !nextOffset.isEmpty { cursor["next_offset"] = nextOffset }
        var page: [String: Any] = [:]
        if totalCount >= 0 { page["count"] = NSNumber(value: totalCount) }

        let payload: [String: Any] = [
            "replies": replyDicts,
            "top_replies": topDicts,
            "cursor": cursor,
            "page": page,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(CommentPage.self, from: jsonData)
    }

    /// ReplyInfo: 1 replies, 2 id, 9 like, 10 ctime, 11 count, 12 content,
    /// 13 member, 14 replyControl(action = 点赞态)。
    private static func decodeReply(_ bytes: [UInt8]) throws -> [String: Any] {
        var reader = BiliProtoReader(bytes: bytes)
        var dict: [String: Any] = [:]
        var nested: [[String: Any]] = []
        var likeState = 0

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .lengthDelimited):
                nested.append(try decodeReply(reader.readLengthDelimited()))
            case (2, .varint):
                dict["rpid"] = NSNumber(value: try reader.readVarint())
            case (9, .varint):
                dict["like"] = NSNumber(value: try reader.readVarint())
            case (10, .varint):
                dict["ctime"] = NSNumber(value: try reader.readVarint())
            case (11, .varint):
                dict["rcount"] = NSNumber(value: try reader.readVarint())
            case (12, .lengthDelimited):
                dict["content"] = try decodeContent(reader.readLengthDelimited())
            case (13, .lengthDelimited):
                dict["member"] = try decodeMember(reader.readLengthDelimited())
            case (14, .lengthDelimited):
                var control = BiliProtoReader(bytes: try reader.readLengthDelimited())
                while !control.isAtEnd {
                    let controlKey = try control.readKey()
                    switch (controlKey.field, controlKey.wire) {
                    case (1, .varint):
                        likeState = Int(try control.readVarint())
                    default:
                        try control.skipField(wire: controlKey.wire)
                    }
                }
            default:
                try reader.skipField(wire: key.wire)
            }
        }

        dict["replies"] = nested
        if likeState != 0 {
            dict["action"] = NSNumber(value: likeState)
        }
        return dict
    }

    /// Content: 1 message, 3 emotes(map<string, Emote>), 9 pictures。
    private static func decodeContent(_ bytes: [UInt8]) throws -> [String: Any] {
        var reader = BiliProtoReader(bytes: bytes)
        var dict: [String: Any] = [:]
        var emotes: [String: Any] = [:]
        var pictures: [[String: Any]] = []

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .lengthDelimited):
                dict["message"] = try reader.readString()
            case (3, .lengthDelimited):
                var entry = BiliProtoReader(bytes: try reader.readLengthDelimited())
                var emoteKey = ""
                var emoteValue: [String: Any] = [:]
                while !entry.isAtEnd {
                    let entryKey = try entry.readKey()
                    switch (entryKey.field, entryKey.wire) {
                    case (1, .lengthDelimited):
                        emoteKey = try entry.readString()
                    case (2, .lengthDelimited):
                        emoteValue = try decodeEmote(entry.readLengthDelimited())
                    default:
                        try entry.skipField(wire: entryKey.wire)
                    }
                }
                if !emoteKey.isEmpty {
                    emotes[emoteKey] = emoteValue
                }
            case (9, .lengthDelimited):
                pictures.append(try decodePicture(reader.readLengthDelimited()))
            default:
                try reader.skipField(wire: key.wire)
            }
        }

        dict["emote"] = emotes
        dict["pictures"] = pictures
        return dict
    }

    /// Emote: 2 url, 7 gifUrl, 8 text。
    private static func decodeEmote(_ bytes: [UInt8]) throws -> [String: Any] {
        var reader = BiliProtoReader(bytes: bytes)
        var dict: [String: Any] = [:]
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (2, .lengthDelimited):
                dict["url"] = try reader.readString()
            case (7, .lengthDelimited):
                dict["gif_url"] = try reader.readString()
            case (8, .lengthDelimited):
                dict["text"] = try reader.readString()
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return dict
    }

    /// Picture: 1 imgSrc, 2 imgWidth, 3 imgHeight。
    private static func decodePicture(_ bytes: [UInt8]) throws -> [String: Any] {
        var reader = BiliProtoReader(bytes: bytes)
        var dict: [String: Any] = [:]
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .lengthDelimited):
                dict["src"] = try reader.readString()
            case (2, .varint):
                dict["width"] = NSNumber(value: try reader.readVarint())
            case (3, .varint):
                dict["height"] = NSNumber(value: try reader.readVarint())
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return dict
    }

    /// Member: 1 mid, 2 name, 4 face, 5 level。
    private static func decodeMember(_ bytes: [UInt8]) throws -> [String: Any] {
        var reader = BiliProtoReader(bytes: bytes)
        var dict: [String: Any] = [:]
        var level = 0
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .varint):
                dict["mid"] = String(try reader.readVarint())
            case (2, .lengthDelimited):
                dict["uname"] = try reader.readString()
            case (4, .lengthDelimited):
                dict["avatar"] = try reader.readString()
            case (5, .varint):
                level = Int(try reader.readVarint())
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        if level > 0 {
            dict["level_info"] = ["current_level": NSNumber(value: level)]
        }
        return dict
    }
}

extension BiliAPIClient {
    /// gRPC 评论分页。失败由调用方回退网页接口；凭据不足（游客模式）时直接抛错。
    func fetchCommentsViaGrpc(
        oid: Int,
        type: Int,
        cursor: String,
        sort: CommentSort
    ) async throws -> CommentPage {
        let context = await videoListenPlaylistRequestContext()
        let accessKey = context.appAccessKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 没有 app 登录凭据时 gRPC 必被拒：直接抛错交回网页接口，
        // 省掉两次无谓往返（游客/未登录场景）。
        guard !context.guestModeEnabled, !accessKey.isEmpty else {
            throw BiliReplyMainListCodec.CodecError.invalidResponse
        }
        let buvid =
            Self.cookieValue(named: "buvid3", in: context.cookieHeader)
            ?? Self.cookieValue(named: "buvid4", in: context.cookieHeader)
            ?? Self.cookieValue(named: "buvid3", in: context.anonymousCookieHeader)
            ?? Self.cookieValue(named: "buvid4", in: context.anonymousCookieHeader)
            ?? ""
        let profile = BiliAppSigner.Profile.androidHD
        let headers = BiliListenerPlaylistCodec.grpcHeaders(
            accessKey: accessKey,
            buvid: buvid,
            networkClass: PlaybackEnvironment.current.networkClass,
            traceID: Self.piliPlusTraceID()
        )
        let message = BiliReplyMainListCodec.encodeRequest(
            oid: oid,
            type: type,
            sort: sort,
            offset: cursor
        )
        var request = try await makeRequest(
            base: appURL,
            path: BiliReplyMainListCodec.endpointPath,
            query: [:],
            referer: "https://www.bilibili.com",
            userAgent: profile.userAgent,
            cookieHeader: context.cookieHeader,
            additionalHeaders: headers,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.httpBody = BiliListenerPlaylistCodec.frame(message)

        let (data, response) = try await self.data(
            for: request,
            priority: URLSessionTask.highPriority,
            retryPolicy: .api
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BiliReplyMainListCodec.CodecError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BiliReplyMainListCodec.CodecError.invalidResponse
        }
        if let biliStatus = httpResponse.value(forHTTPHeaderField: "bili-status-code"),
           Int(biliStatus) ?? 1 != 0 {
            throw BiliReplyMainListCodec.CodecError.invalidResponse
        }
        if let grpcStatus = httpResponse.value(forHTTPHeaderField: "grpc-status"),
           Int(grpcStatus) ?? 1 != 0 {
            throw BiliReplyMainListCodec.CodecError.invalidResponse
        }
        let payload = try BiliListenerPlaylistCodec.unframe(data)
        return try BiliReplyMainListCodec.decodePage(payload)
    }
}

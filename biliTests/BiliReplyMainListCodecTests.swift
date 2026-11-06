import XCTest
@testable import bili

/// 评论 gRPC 分页编解码的往返测试：构造假 MainListReply 报文 → decodePage，
/// 断言字段映射与现有 CommentPage 模型一致。
final class BiliReplyMainListCodecTests: XCTestCase {
    func testDecodePageMapsFieldsToCommentPage() throws {
        var main = BiliProtoWriter()

        // field 1 CursorReply: 1 next, 4 isEnd
        main.appendMessage(field: 1) { cursor in
            cursor.appendString(field: 1, value: "123456")
            cursor.appendVarint(field: 4, value: 0)
        }
        // field 2 replies
        main.appendMessage(field: 2) { reply in
            reply.appendVarint(field: 2, value: 1001)
            reply.appendVarint(field: 9, value: 23)
            reply.appendVarint(field: 10, value: 1_700_000_000)
            reply.appendVarint(field: 11, value: 4)
            reply.appendMessage(field: 12) { content in
                content.appendString(field: 1, value: "第一条评论[doge]")
                // field 9 picture
                content.appendMessage(field: 9) { picture in
                    picture.appendString(field: 1, value: "https://imgs.example/p1.jpg")
                    picture.appendVarint(field: 2, value: 800)
                    picture.appendVarint(field: 3, value: 600)
                }
                // field 3 emotes map entry: 1 key, 2 value
                content.appendMessage(field: 3) { entry in
                    entry.appendString(field: 1, value: "[doge]")
                    entry.appendMessage(field: 2) { emote in
                        emote.appendString(field: 2, value: "https://emo.example/doge.png")
                        emote.appendString(field: 8, value: "[doge]")
                    }
                }
            }
            reply.appendMessage(field: 13) { member in
                member.appendVarint(field: 1, value: 9_999)
                member.appendString(field: 2, value: "评论用户")
                member.appendString(field: 4, value: "https://faces.example/face.jpg")
                member.appendVarint(field: 5, value: 6)
            }
            reply.appendMessage(field: 14) { control in
                control.appendVarint(field: 1, value: 1)
            }
            // field 1 嵌套回复
            reply.appendMessage(field: 1) { nested in
                nested.appendVarint(field: 2, value: 2002)
                nested.appendMessage(field: 12) { content in
                    content.appendString(field: 1, value: "嵌套回复内容")
                }
            }
        }
        // field 3 SubjectControl: 16 count
        main.appendMessage(field: 3) { subject in
            subject.appendVarint(field: 16, value: 60)
        }
        // field 14 topReplies
        main.appendMessage(field: 14) { reply in
            reply.appendVarint(field: 2, value: 3003)
            reply.appendMessage(field: 12) { content in
                content.appendString(field: 1, value: "置顶评论")
            }
        }
        // field 20 FeedPaginationReply: 1 nextOffset
        main.appendMessage(field: 20) { pagination in
            pagination.appendString(field: 1, value: "offset-token-abc")
        }

        let payload = try BiliListenerPlaylistCodec.unframe(
            BiliListenerPlaylistCodec.frame(main.data)
        )
        let page = try BiliReplyMainListCodec.decodePage(payload)

        XCTAssertEqual(page.replies?.count, 1)
        let reply = try XCTUnwrap(page.replies?.first)
        XCTAssertEqual(reply.rpid, 1001)
        XCTAssertEqual(reply.like, 23)
        XCTAssertEqual(reply.ctime, 1_700_000_000)
        XCTAssertEqual(reply.replyCount, 4)
        XCTAssertEqual(reply.likeState, 1)
        XCTAssertEqual(reply.content?.message, "第一条评论[doge]")
        XCTAssertEqual(reply.member?.uname, "评论用户")
        XCTAssertEqual(reply.member?.mid, "9999")
        XCTAssertEqual(reply.member?.avatar, "https://faces.example/face.jpg")
        XCTAssertEqual(reply.member?.levelInfo?.currentLevel, 6)
        XCTAssertEqual(reply.replies?.first?.rpid, 2002)
        XCTAssertEqual(reply.replies?.first?.content?.message, "嵌套回复内容")

        let emote = try XCTUnwrap(reply.content?.emote(for: "[doge]"))
        XCTAssertEqual(emote.url, "https://emo.example/doge.png")
        XCTAssertEqual(emote.text, "[doge]")

        XCTAssertEqual(reply.content?.pictures.count, 1)
        XCTAssertEqual(
            reply.content?.pictures.first?.url,
            "https://imgs.example/p1.jpg"
        )
        XCTAssertEqual(reply.content?.pictures.first?.width, 800)
        XCTAssertEqual(reply.content?.pictures.first?.height, 600)

        XCTAssertEqual(page.topReplies?.count, 1)
        XCTAssertEqual(page.topReplies?.first?.rpid, 3003)
        XCTAssertEqual(page.topReplies?.first?.content?.message, "置顶评论")

        let cursor = try XCTUnwrap(page.cursor)
        XCTAssertEqual(cursor.effectiveNext, "offset-token-abc")
        XCTAssertEqual(cursor.isEnd, false)
        XCTAssertEqual(page.page?.count, 60)
    }

    func testEncodeRequestWritesCursorAndMode() throws {
        let hotData = BiliReplyMainListCodec.encodeRequest(
            oid: 123, type: 1, sort: .hot, offset: "tok"
        )
        var reader = BiliProtoReader(data: hotData)
        var oid = 0
        var type = 0
        var mode = 0
        var offset = ""
        var pageSize = 0
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .varint): oid = Int(try reader.readVarint())
            case (2, .varint): type = Int(try reader.readVarint())
            case (9, .varint): mode = Int(try reader.readVarint())
            case (10, .lengthDelimited):
                var pagination = BiliProtoReader(bytes: try reader.readLengthDelimited())
                while !pagination.isAtEnd {
                    let paginationKey = try pagination.readKey()
                    switch (paginationKey.field, paginationKey.wire) {
                    case (1, .varint): pageSize = Int(try pagination.readVarint())
                    case (2, .lengthDelimited): offset = try pagination.readString()
                    default: try pagination.skipField(wire: paginationKey.wire)
                    }
                }
            default: try reader.skipField(wire: key.wire)
            }
        }
        XCTAssertEqual(oid, 123)
        XCTAssertEqual(type, 1)
        XCTAssertEqual(mode, 3, "hot 对应 MAIN_LIST_HOT=3")
        XCTAssertEqual(pageSize, 20)
        XCTAssertEqual(offset, "tok")

        let timeData = BiliReplyMainListCodec.encodeRequest(
            oid: 123, type: 1, sort: .time, offset: nil
        )
        var timeMode = 0
        var timeReader = BiliProtoReader(data: timeData)
        while !timeReader.isAtEnd {
            let key = try timeReader.readKey()
            switch (key.field, key.wire) {
            case (9, .varint): timeMode = Int(try timeReader.readVarint())
            default: try timeReader.skipField(wire: key.wire)
            }
        }
        XCTAssertEqual(timeMode, 2, "time 对应 MAIN_LIST_TIME=2")
    }
}

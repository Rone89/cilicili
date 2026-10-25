import XCTest
@testable import bili

final class CommentLocationMetadataTests: XCTestCase {
    func testDecodesServiceRegionAndNestedReplyRegions() throws {
        let comment = try decode([
            "reply_control": ["location": "IP属地：广东"],
            "replies": [
                ["rpid": 2, "reply_control": ["location": "IP属地：上海"]]
            ],
        ])
        XCTAssertEqual(comment.locationText, "IP属地：广东")
        XCTAssertEqual(comment.replies?.first?.locationText, "IP属地：上海")
        XCTAssertEqual(comment.metadataText(timeText: "2小时前"), "2小时前 · IP属地：广东")
    }

    func testMissingNullBlankAndMalformedMetadataKeepCommentDecodable() throws {
        let samples: [[String: Any]] = [
            [:], ["reply_control": NSNull()], ["reply_control": [:]],
            ["reply_control": ["location": NSNull()]],
            ["reply_control": ["location": "  \n  "]],
            ["reply_control": ["location": 123]],
            ["reply_control": "unexpected"],
            ["reply_control": ["location": ["unexpected": true]]],
        ]
        for sample in samples {
            let comment = try decode(sample)
            XCTAssertNil(comment.locationText, "\(sample)")
            XCTAssertEqual(comment.content?.message, "正文")
            XCTAssertEqual(comment.metadataText(timeText: "昨天"), "昨天")
            XCTAssertEqual(comment.metadataText(timeText: ""), "")
        }
    }

    func testRegionOnlyAndWhitespaceDoNotAddEmptyTimeSeparators() throws {
        let comment = try decode(["reply_control": ["location": "  IP属地：广东\n "]])
        XCTAssertEqual(comment.metadataText(timeText: ""), "IP属地：广东")
    }

    @MainActor
    func testVideoAndDynamicDisplayModelsRetainRegionChanges() throws {
        let first = try decode(["reply_control": ["location": "IP属地：广东"]])
        let changed = try decode(["reply_control": ["location": "IP属地：上海"]])
        let video = VideoDetailCommentDisplayModel(comment: first)
        let dynamic = DynamicCommentRowDisplayModel(comment: first)
        XCTAssertTrue(video.metadataText.contains("IP属地：广东"))
        XCTAssertEqual(video.metadataText, dynamic.metadataText)
        XCTAssertNotEqual(video, VideoDetailCommentDisplayModel(comment: changed))
        XCTAssertNotEqual(dynamic, DynamicCommentRowDisplayModel(comment: changed))
    }

    func testRegionChangesInvalidateListAndReplyCaches() throws {
        let first = try decode(["reply_control": ["location": "IP属地：广东"]])
        let changed = try decode(["reply_control": ["location": "IP属地：上海"]])
        XCTAssertNotEqual(VideoDetailCommentListSignature([first]), VideoDetailCommentListSignature([changed]))
        XCTAssertNotEqual(DynamicCommentListSignature([first]), DynamicCommentListSignature([changed]))
        XCTAssertNotEqual(
            VideoDetailCommentReplyDisplaySignature(rootComment: first, replies: [first]),
            VideoDetailCommentReplyDisplaySignature(rootComment: first, replies: [changed])
        )
        XCTAssertNotEqual(
            DynamicCommentReplyItemSignature(rootComment: first, replies: [first]),
            DynamicCommentReplyItemSignature(rootComment: first, replies: [changed])
        )
    }

    private func decode(_ fields: [String: Any]) throws -> Comment {
        var json: [String: Any] = [
            "rpid": 1, "content": ["message": "正文"],
        ]
        json.merge(fields) { _, new in new }
        return try JSONDecoder().decode(
            Comment.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
    }
}

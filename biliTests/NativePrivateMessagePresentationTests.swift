import XCTest
import UIKit
@testable import bili

final class NativePrivateMessagePresentationTests: XCTestCase {
    func testTimelineSeparatesFiveMinuteGapsAndSenderChanges() {
        let entries = NativePrivateMessageTimeline.entries([
            message(1, sender: 2, time: 0), message(2, sender: 2, time: 20),
            message(3, sender: 1, time: 40), message(4, sender: 1, time: 339),
            message(5, sender: 1, time: 639)
        ])
        XCTAssertEqual(entries.map(\.showsTimestamp), [true, false, false, false, true])
        XCTAssertEqual(entries.map(\.startsSenderGroup), [true, false, true, false, true])
        XCTAssertEqual(entries.map(\.id), [1, 2, 3, 4, 5])
    }

    func testTimelineSeparatesDaysEvenWithoutFiveMinuteGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let entries = NativePrivateMessageTimeline.entries([
            message(1, sender: 2, time: 86_390), message(2, sender: 2, time: 86_400)
        ], calendar: calendar)
        XCTAssertTrue(entries[1].showsTimestamp)
        XCTAssertTrue(entries[1].startsSenderGroup)
    }

    func testTimelineDoesNotInventMissingDatesOrChangeMessageIdentity() {
        let withoutDate = message(1, sender: 2, time: nil)
        let withDate = message(2, sender: 2, time: 30)
        let entries = NativePrivateMessageTimeline.entries([withoutDate, withDate])
        XCTAssertFalse(entries[0].showsTimestamp)
        XCTAssertTrue(entries[1].showsTimestamp)
        XCTAssertEqual(entries.map(\.message), [withoutDate, withDate])
        XCTAssertTrue(NativePrivateMessageTimeline.entries([]).isEmpty)
    }

    @MainActor
    func testShortEmoteMessageFitsOneLineAtStandardAndAccessibilitySizes() {
        let emotes = ["[doge]": BiliInlineEmote(token: "[doge]", url: "https://example.com/doge.png", width: 32, height: 32)]
        for category: UIContentSizeCategory in [.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            let font = AppTypography.Role.messageBody.uiFont(contentSizeCategory: category)
            for text in ["[doge]好的", "😀好的", "好的"] {
                let width = PrivateMessageTextLayout.width(text: text, inlineEmotes: emotes, font: font, maximumWidth: 300)
                let label = UILabel()
                label.numberOfLines = 0
                label.attributedText = PrivateMessageTextLayout.attributedText(text: text, inlineEmotes: emotes, font: font)
                let height = label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
                let unconstrainedHeight = label.sizeThatFits(CGSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)).height
                XCTAssertEqual(height, unconstrainedHeight, accuracy: 1, "Unexpected wrap: \(text), \(category)")
            }
        }
    }

    @MainActor
    func testWideAttachmentsAndLongMessagesRespectAvailableWidth() {
        let font = AppTypography.Role.messageBody.uiFont(contentSizeCategory: .large)
        let emotes = ["[wide]": BiliInlineEmote(token: "[wide]", url: "https://example.com/wide.png", width: 128, height: 32)]
        let wide = PrivateMessageTextLayout.width(text: "[wide]好的", inlineEmotes: emotes, font: font, maximumWidth: 300)
        let plain = PrivateMessageTextLayout.width(text: "口好的", inlineEmotes: [:], font: font, maximumWidth: 300)
        XCTAssertGreaterThan(wide, plain)
        let long = PrivateMessageTextLayout.width(text: String(repeating: "多行中文😀English", count: 30), inlineEmotes: [:], font: font, maximumWidth: 180)
        XCTAssertLessThanOrEqual(long, 180)
        XCTAssertGreaterThan(long, 150)
        let multiline = PrivateMessageTextLayout.width(text: "好的\n再见", inlineEmotes: [:], font: font, maximumWidth: 300)
        XCTAssertLessThan(multiline, 100)
    }

    private func message(_ id: Int, sender: Int, time: TimeInterval?) -> AccountPrivateMessage {
        AccountPrivateMessage(sequence: id, messageKey: id, messageType: 1, senderID: sender,
                              text: "正文 😀", imageURLString: nil, routeURL: nil,
                              timestamp: time.map { Date(timeIntervalSince1970: $0) },
                              isOutgoing: sender == 1, isWithdrawn: false)
    }
}

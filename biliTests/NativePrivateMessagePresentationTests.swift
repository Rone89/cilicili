import XCTest
@testable import bili

final class NativePrivateMessagePresentationTests: XCTestCase {
    @MainActor
    func testExperimentDefaultsOffAndPersistsWithoutClearingLibraryData() {
        let name = "NativePrivateMessageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("existing", forKey: "unrelated.library.data")
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.nativePrivateMessageConversationExperimentEnabled)
        store.setNativePrivateMessageConversationExperimentEnabled(true)
        XCTAssertTrue(store.nativePrivateMessageConversationExperimentEnabled)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).nativePrivateMessageConversationExperimentEnabled)
        store.setNativePrivateMessageConversationExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).nativePrivateMessageConversationExperimentEnabled)
        XCTAssertEqual(defaults.string(forKey: "unrelated.library.data"), "existing")
    }

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

    private func message(_ id: Int, sender: Int, time: TimeInterval?) -> AccountPrivateMessage {
        AccountPrivateMessage(sequence: id, messageKey: id, messageType: 1, senderID: sender,
                              text: "正文 😀", imageURLString: nil, routeURL: nil,
                              timestamp: time.map { Date(timeIntervalSince1970: $0) },
                              isOutgoing: sender == 1, isWithdrawn: false)
    }
}

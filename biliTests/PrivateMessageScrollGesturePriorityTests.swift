import UIKit
import XCTest
@testable import bili

final class PrivateMessageScrollGesturePriorityTests: XCTestCase {
    @MainActor
    func testMessageScrollWaitsForBothBackGesturesWithoutChangingDelegates() throws {
        let root = UIViewController()
        let conversation = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        navigation.pushViewController(conversation, animated: false)
        conversation.loadViewIfNeeded()
        let messages = RecordingScrollView()
        let otherScroll = RecordingScrollView()
        conversation.view.addSubview(messages)
        conversation.view.addSubview(otherScroll)
        let probe = PrivateMessageScrollGesturePriority.ProbeView()
        messages.addSubview(probe)
        let edge = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
        let content = try XCTUnwrap(navigation.interactiveContentPopGestureRecognizer)
        let edgeDelegate = edge.delegate
        let contentDelegate = content.delegate
        let edgeEnabled = edge.isEnabled
        let contentEnabled = content.isEnabled

        probe.prioritizeNavigationGestures()
        probe.prioritizeNavigationGestures()

        XCTAssertEqual(messages.recordingPan.dependencies.count, 2)
        XCTAssertTrue(messages.recordingPan.dependencies.contains { $0 === edge })
        XCTAssertTrue(messages.recordingPan.dependencies.contains { $0 === content })
        XCTAssertTrue(otherScroll.recordingPan.dependencies.isEmpty)
        XCTAssertTrue(edge.delegate === edgeDelegate)
        XCTAssertTrue(content.delegate === contentDelegate)
        XCTAssertEqual(edge.isEnabled, edgeEnabled)
        XCTAssertEqual(content.isEnabled, contentEnabled)
    }
}

@MainActor
private final class RecordingScrollView: UIScrollView {
    let recordingPan = RecordingPanGestureRecognizer()
    override var panGestureRecognizer: UIPanGestureRecognizer { recordingPan }
}

@MainActor
private final class RecordingPanGestureRecognizer: UIPanGestureRecognizer {
    var dependencies = [UIGestureRecognizer]()
    override func require(toFail otherGestureRecognizer: UIGestureRecognizer) {
        dependencies.append(otherGestureRecognizer)
    }
}

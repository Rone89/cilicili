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
    @MainActor
    func testRefreshPresentationRestoresWithoutEndingAnActiveRefresh() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKey() }
        let scroll = UIScrollView(frame: controller.view.bounds)
        controller.view.addSubview(scroll)
        let control = UIRefreshControl()
        scroll.refreshControl = control
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        control.beginRefreshing()
        XCTAssertTrue(control.isRefreshing, "Positive control must be refreshing before the lease")
        let lease = PrivateMessageScrollGesturePriority.RefreshPresentationLease()
        lease.suspend(control)
        lease.suspend(control)
        XCTAssertEqual(control.alpha, 0)
        XCTAssertTrue(control.isRefreshing)
        lease.restore()
        XCTAssertEqual(control.alpha, 1)
        XCTAssertTrue(control.isRefreshing)
        lease.restore()
        XCTAssertEqual(control.alpha, 1)
    }

    @MainActor
    func testRefreshPresentationPreservesOpacityAndRestoresReplacedControl() {
        let hidden = UIRefreshControl()
        hidden.alpha = 0.35
        let visible = UIRefreshControl()
        let replacement = UIRefreshControl()
        let lease = PrivateMessageScrollGesturePriority.RefreshPresentationLease()
        lease.suspend(hidden)
        lease.restore()
        XCTAssertEqual(hidden.alpha, 0.35, accuracy: 0.0001)
        lease.suspend(visible)
        lease.suspend(replacement)
        XCTAssertEqual(visible.alpha, 1)
        XCTAssertEqual(replacement.alpha, 0)
        lease.restore()
        XCTAssertEqual(replacement.alpha, 1)
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

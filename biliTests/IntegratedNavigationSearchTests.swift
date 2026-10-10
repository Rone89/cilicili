import XCTest
import UIKit
@testable import bili

@MainActor
final class IntegratedNavigationSearchTests: XCTestCase {
    func testSearchPresentationDoesNotRestoreStackedPlacement() {
        let (window, owner, bridge) = makeFixture()
        defer { bridge.restorePlacement(); window.isHidden = true }
        XCTAssertEqual(owner.navigationItem.preferredSearchBarPlacement, .integrated)
        XCTAssertFalse(owner.navigationItem.searchBarPlacementAllowsToolbarIntegration)

        bridge.viewWillDisappear(false)
        XCTAssertEqual(owner.navigationItem.preferredSearchBarPlacement, .integrated)
    }

    func testNavigationItemChangesAreCorrectedWithoutAnotherBridgeLayout() {
        let (window, owner, bridge) = makeFixture()
        defer { bridge.restorePlacement(); window.isHidden = true }
        let item = owner.navigationItem
        item.preferredSearchBarPlacement = .stacked
        item.searchBarPlacementAllowsToolbarIntegration = true
        item.searchController = UISearchController(searchResultsController: nil)

        let corrected = expectation(for: NSPredicate { _, _ in
            item.preferredSearchBarPlacement == .integrated
                && !item.searchBarPlacementAllowsToolbarIntegration
        }, evaluatedWith: nil)
        wait(for: [corrected], timeout: 2)
    }

    func testDismantlingRestoresPreferencesAndStopsCorrections() {
        let (window, owner, bridge) = makeFixture()
        defer { window.isHidden = true }
        bridge.restorePlacement()
        XCTAssertEqual(owner.navigationItem.preferredSearchBarPlacement, .stacked)
        XCTAssertTrue(owner.navigationItem.searchBarPlacementAllowsToolbarIntegration)
        owner.navigationItem.preferredSearchBarPlacement = .automatic
        bridge.applyPlacement()
        bridge.restorePlacement()
        XCTAssertEqual(owner.navigationItem.preferredSearchBarPlacement, .automatic)
    }

    func testPushedDestinationIsNotReconfigured() {
        let (window, owner, bridge) = makeFixture()
        defer { bridge.restorePlacement(); window.isHidden = true }
        let detail = UIViewController()
        detail.navigationItem.searchController = UISearchController(searchResultsController: nil)
        detail.navigationItem.preferredSearchBarPlacement = .stacked
        owner.navigationController?.pushViewController(detail, animated: false)
        bridge.applyPlacement()
        XCTAssertEqual(detail.navigationItem.preferredSearchBarPlacement, .stacked)
    }

    private func makeFixture() -> (UIWindow, UIViewController, IntegratedNavigationSearch.Controller) {
        let owner = UIViewController()
        owner.navigationItem.searchController = UISearchController(searchResultsController: nil)
        owner.navigationItem.preferredSearchBarPlacement = .stacked
        let navigation = UINavigationController(rootViewController: owner)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = navigation
        window.isHidden = false
        navigation.view.layoutIfNeeded()
        let bridge = IntegratedNavigationSearch.Controller()
        owner.addChild(bridge)
        owner.view.addSubview(bridge.view)
        bridge.didMove(toParent: owner)
        bridge.applyPlacement()
        return (window, owner, bridge)
    }
}

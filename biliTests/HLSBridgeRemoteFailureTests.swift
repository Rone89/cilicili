import XCTest
@testable import bili

final class HLSBridgeRemoteFailureTests: XCTestCase {
    func testHTTPStatusReasonMatrix() {
        assertHTTPStatus(
            401,
            category: .authDenied,
            allowsAVPlayerToKSFallback: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 403
        )
        assertHTTPStatus(
            403,
            category: .authDenied,
            allowsAVPlayerToKSFallback: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 403
        )
        assertHTTPStatus(
            404,
            category: .urlExpired,
            allowsAVPlayerToKSFallback: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 410
        )
        assertHTTPStatus(
            410,
            category: .urlExpired,
            allowsAVPlayerToKSFallback: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 410
        )
        assertHTTPStatus(
            416,
            category: .rangeUnsupported,
            allowsAVPlayerToKSFallback: true,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 416
        )
        assertHTTPStatus(
            429,
            category: .rateLimited,
            allowsAVPlayerToKSFallback: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 429
        )
        assertHTTPStatus(
            503,
            category: .serverUnavailable,
            allowsAVPlayerToKSFallback: true,
            allowsSameSourceRecovery: true,
            proxyStatusCode: 502
        )
    }

    func testURLErrorReasonMatrix() {
        let cancelled = HLSBridgeRemoteFailure.reason(for: URLError(.cancelled))
        XCTAssertEqual(cancelled.category, .cancelled)
        XCTAssertFalse(cancelled.allowsAVPlayerToKSFallback)
        XCTAssertFalse(cancelled.shouldRecordSourceFailure)
        XCTAssertEqual(cancelled.proxyHTTPStatus.statusCode, 499)

        let timedOut = HLSBridgeRemoteFailure.reason(for: URLError(.timedOut))
        XCTAssertEqual(timedOut.category, .timeout)
        XCTAssertTrue(timedOut.allowsAVPlayerToKSFallback)
        XCTAssertTrue(timedOut.allowsSameSourceRecovery)
        XCTAssertEqual(timedOut.proxyHTTPStatus.statusCode, 504)
    }

    func testUnknownErrorFallsBackToKSPlayer() {
        let reason = HLSBridgeRemoteFailure.reason(for: NSError(
            domain: "HLSBridgeRemoteFailureTests",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "boom"]
        ))
        XCTAssertEqual(reason.category, .unknown)
        XCTAssertTrue(reason.allowsAVPlayerToKSFallback)
        XCTAssertTrue(reason.allowsSameSourceRecovery)
        XCTAssertEqual(reason.proxyHTTPStatus.statusCode, 502)
    }

    private func assertHTTPStatus(
        _ statusCode: Int,
        category: HLSBridgeRemoteFailureCategory,
        allowsAVPlayerToKSFallback: Bool,
        allowsSameSourceRecovery: Bool,
        proxyStatusCode: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let reason = HLSBridgeRemoteFailure.reason(forHTTPStatus: statusCode) else {
            XCTFail("Expected reason for HTTP \(statusCode)", file: file, line: line)
            return
        }
        XCTAssertEqual(reason.category, category, file: file, line: line)
        XCTAssertEqual(reason.allowsAVPlayerToKSFallback, allowsAVPlayerToKSFallback, file: file, line: line)
        XCTAssertEqual(reason.allowsSameSourceRecovery, allowsSameSourceRecovery, file: file, line: line)
        XCTAssertEqual(reason.proxyHTTPStatus.statusCode, proxyStatusCode, file: file, line: line)
    }
}

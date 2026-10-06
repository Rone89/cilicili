import XCTest
@testable import bili

final class CellularBiliTrafficCompatibilityTests: XCTestCase {
    func testClassifiesOnlyApprovedBiliDomainSuffixes() {
        XCTAssertEqual(
            CellularBiliTrafficCompatibility.classify(host: "upos-sz-mirrorcos.bilivideo.com"),
            .bili
        )
        XCTAssertEqual(
            CellularBiliTrafficCompatibility.classify(host: "xy1.mcdn.bilivideo.cn"),
            .bili
        )
        XCTAssertEqual(
            CellularBiliTrafficCompatibility.classify(host: "bilivideo.com.example.test"),
            .external
        )
        XCTAssertEqual(
            CellularBiliTrafficCompatibility.classify(host: "upos-hz-mirrorakam.akamaized.net"),
            .external
        )
        XCTAssertEqual(CellularBiliTrafficCompatibility.classify(host: nil), .unknown)
    }

    func testPrioritizesApprovedBiliDomainsOnlyOnCellular() {
        let external = URL(string: "https://upos-hz-mirrorakam.akamaized.net/video.m4s")!
        let bilivideo = URL(string: "https://upos-sz-mirrorcos.bilivideo.com/video.m4s")!
        let bilivideoCN = URL(string: "https://xy1.mcdn.bilivideo.cn/audio.m4s")!
        let urls = [external, bilivideo, bilivideoCN]

        XCTAssertEqual(
            CellularBiliTrafficCompatibility.prioritizedURLs(urls, isCellularNetwork: true),
            [bilivideo, bilivideoCN, external]
        )
        XCTAssertEqual(
            CellularBiliTrafficCompatibility.prioritizedURLs(urls, isCellularNetwork: false),
            urls
        )
    }
}

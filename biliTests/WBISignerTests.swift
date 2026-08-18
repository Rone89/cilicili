import XCTest

@testable import bili

final class WBISignerTests: XCTestCase {
    func testWBISigningMatchesKnownVector() {
        let signed = WBISigner.sign(
            [
                "foo": "114",
                "bar": "514",
                "baz": "1919810",
            ],
            keys: WBIKeys(
                imgKey: "7cd084941338484aae1ad9425b84077c",
                subKey: "4932caff0ff746eab6f01bf08b70ac45"
            ),
            timestamp: 1_702_204_169
        )

        XCTAssertEqual(signed["wts"], "1702204169")
        XCTAssertEqual(signed["w_rid"], "6149fdadf571698ca7e6a567265cd0ee")
    }

    func testWBISigningRemovesForbiddenCharactersBeforeEncoding() {
        let plain = WBISigner.sign(
            ["value": "a!b'c(d)e*f"],
            keys: WBIKeys(imgKey: "img", subKey: "sub"),
            timestamp: 123
        )
        let sanitized = WBISigner.sign(
            ["value": "abcdef"],
            keys: WBIKeys(imgKey: "img", subKey: "sub"),
            timestamp: 123
        )

        XCTAssertEqual(plain["w_rid"], sanitized["w_rid"])
    }

    func testAppSigningMatchesKnownVector() {
        let signed = BiliAppSigner.sign(
            ["foo": "bar"],
            profile: .androidHD,
            timestamp: 1_700_000_000
        )

        XCTAssertEqual(signed["appkey"], "dfca71928277209b")
        XCTAssertEqual(signed["ts"], "1700000000")
        XCTAssertEqual(signed["sign"], "5715c2fc5656adb7481073692a9d8031")
    }
}

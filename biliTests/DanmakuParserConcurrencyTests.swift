import Foundation
import XCTest

@testable import bili

@MainActor
final class DanmakuParserConcurrencyTests: XCTestCase {
    func testDetachedXMLParserMatchesDirectParserAndHonorsContextLimit() async throws {
        let data = Data(
            #"<?xml version="1.0"?><i><d p="1.5,1,25,16777215,0,0,0,first"> first </d><d p="2,4,30,255,0,0,0,second">second</d><d p="3,1,25,1">beyond limit</d></i>"#
                .utf8
        )
        let context = DanmakuXMLParseContext(cid: 42, maxItems: 2)

        let direct = try DanmakuXMLParser(cid: context.cid, maxItems: context.maxItems).parse(data: data)
        let detached = try await BiliAPIClient.parseDanmakuXML(data, context: context)

        XCTAssertEqual(detached, direct)
        XCTAssertEqual(detached.map(\.id), ["42-first-0", "42-second-1"])
        XCTAssertEqual(detached.map(\.text), ["first", "second"])
    }

    func testDetachedProtobufParserMatchesDirectParserAndHonorsContextLimit() async throws {
        let data = protobufSegment([
            element(id: 10, progress: 1_500, mode: 1, text: " first "),
            element(id: 11, progress: 2_000, mode: 4, text: "second"),
            element(id: 12, progress: 3_000, mode: 1, text: "beyond limit"),
        ])
        let context = DanmakuSegmentParseContext(cid: 42, segmentIndex: 3, maxItems: 2)

        let direct = try DanmakuSegmentProtobufParser(
            cid: context.cid,
            segmentIndex: context.segmentIndex,
            maxItems: context.maxItems
        )
        .parse(data: data)
        let detached = try await BiliAPIClient.parseDanmakuSegment(data, context: context)

        XCTAssertEqual(detached, direct)
        XCTAssertEqual(detached.map(\.id), ["42-seg3-10", "42-seg3-11"])
        XCTAssertEqual(detached.map(\.text), ["first", "second"])
    }

    func testDetachedParsersPreserveMalformedInputErrors() async {
        let xml = Data("<i><d".utf8)
        let protobuf = Data([0x0A, 0x02, 0x08])

        let directXMLError = thrownError {
            try DanmakuXMLParser(cid: 1).parse(data: xml)
        }
        let detachedXMLError = await thrownError {
            try await BiliAPIClient.parseDanmakuXML(xml, context: DanmakuXMLParseContext(cid: 1))
        }
        XCTAssertEqual((directXMLError as NSError?)?.domain, (detachedXMLError as NSError?)?.domain)
        XCTAssertEqual((directXMLError as NSError?)?.code, (detachedXMLError as NSError?)?.code)

        let directProtobufError = thrownError {
            try DanmakuSegmentProtobufParser(cid: 1, segmentIndex: 1).parse(data: protobuf)
        }
        let detachedProtobufError = await thrownError {
            try await BiliAPIClient.parseDanmakuSegment(
                protobuf,
                context: DanmakuSegmentParseContext(cid: 1, segmentIndex: 1)
            )
        }
        XCTAssertTrue(isEmptyDataError(directProtobufError))
        XCTAssertTrue(isEmptyDataError(detachedProtobufError))
    }

    private func thrownError(_ operation: () throws -> [DanmakuItem]) -> Error? {
        do {
            _ = try operation()
            return nil
        } catch {
            return error
        }
    }

    private func thrownError(_ operation: () async throws -> [DanmakuItem]) async -> Error? {
        do {
            _ = try await operation()
            return nil
        } catch {
            return error
        }
    }

    private func isEmptyDataError(_ error: Error?) -> Bool {
        guard let error = error as? BiliAPIError else { return false }
        if case .emptyData = error { return true }
        return false
    }

    private func protobufSegment(_ elements: [Data]) -> Data {
        Data(elements.flatMap { field(number: 1, payload: $0) })
    }

    private func element(id: UInt64, progress: UInt64, mode: UInt64, text: String) -> Data {
        Data(
            field(number: 1, value: id)
                + field(number: 2, value: progress)
                + field(number: 3, value: mode)
                + field(number: 4, value: 25)
                + field(number: 5, value: 0xFF_FF_FF)
                + field(number: 7, payload: Data(text.utf8))
        )
    }

    private func field(number: UInt64, value: UInt64) -> [UInt8] {
        var bytes = varint(number << 3)
        bytes.append(contentsOf: varint(value))
        return bytes
    }

    private func field(number: UInt64, payload: Data) -> [UInt8] {
        var bytes = varint((number << 3) | 2)
        bytes.append(contentsOf: varint(UInt64(payload.count)))
        bytes.append(contentsOf: payload)
        return bytes
    }

    private func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes = [UInt8]()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }
}

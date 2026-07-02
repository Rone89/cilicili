import XCTest
@testable import bili

final class DolbyVisionCodecConfigurationTests: XCTestCase {
    func testParsesProfileEightHDR10CompatibleConfiguration() {
        let configuration = DolbyVisionCodecConfiguration.parse(
            from: makeInitializationData(
                boxType: "dvcC",
                payload: makePayload(profile: 8, level: 6, compatibilityID: 1)
            )
        )

        XCTAssertEqual(configuration?.profile, 8)
        XCTAssertEqual(configuration?.level, 6)
        XCTAssertEqual(configuration?.baseLayerSignalCompatibilityID, 1)
        XCTAssertEqual(configuration?.decoderCodecString, "dvh1.08.06")
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(baseLayerCodec: "hev1.2.4.L150.b0"), "hvc1.2.4.L150.b0")
        XCTAssertEqual(configuration?.supplementalCodecString, "dvh1.08.06/db1p")
        XCTAssertEqual(configuration?.hlsVideoRangeAttribute, "PQ")
    }

    func testNormalizesProfileEightHEVCSampleEntryForHLS() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hev1",
            boxType: "dvcC",
            payload: makePayload(profile: 8, level: 6, compatibilityID: 1)
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(data)

        XCTAssertEqual(normalization?.originalSampleEntryType, "hev1")
        XCTAssertEqual(normalization?.hlsSampleEntryType, "hvc1")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "hvc1")
    }

    func testProfileFiveAdvertisesDolbyVisionCodecDirectly() {
        let configuration = DolbyVisionCodecConfiguration.parse(
            from: makeInitializationData(
                boxType: "dvcC",
                payload: makePayload(profile: 5, level: 6, compatibilityID: 0)
            )
        )

        XCTAssertEqual(configuration?.decoderCodecString, "dvh1.05.06")
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(baseLayerCodec: "hev1.2.4.L150.b0"), "dvh1.05.06")
    }

    func testNormalizesProfileFiveSampleEntryForHLS() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hev1",
            boxType: "dvcC",
            payload: makePayload(profile: 5, level: 6, compatibilityID: 0)
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(data)

        XCTAssertEqual(normalization?.originalSampleEntryType, "hev1")
        XCTAssertEqual(normalization?.hlsSampleEntryType, "dvh1")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "dvh1")
    }

    func testParsesProfileEightHLGCompatibleConfiguration() {
        let configuration = DolbyVisionCodecConfiguration.parse(
            from: makeInitializationData(
                boxType: "dvvC",
                payload: makePayload(profile: 8, level: 7, compatibilityID: 4)
            )
        )

        XCTAssertEqual(configuration?.supplementalCodecString, "dvh1.08.07/db4h")
        XCTAssertEqual(configuration?.hlsVideoRangeAttribute, "HLG")
    }

    func testParsesAV1ProfileTenConfiguration() {
        let configuration = DolbyVisionCodecConfiguration.parse(
            from: makeInitializationData(
                boxType: "dvwC",
                payload: makePayload(profile: 10, level: 9, compatibilityID: 4)
            )
        )

        XCTAssertEqual(configuration?.supplementalCodecString, "dav1.10.09/db4h")
        XCTAssertEqual(configuration?.hlsVideoRangeAttribute, "HLG")
    }

    func testMissingConfigurationReturnsNil() {
        XCTAssertNil(DolbyVisionCodecConfiguration.parse(from: Data([0, 1, 2, 3, 4, 5])))
    }

    private func makeInitializationData(boxType: String, payload: [UInt8]) -> Data {
        var bytes = [UInt8]([0, 0, 0, 16, 102, 116, 121, 112, 105, 115, 111, 109, 0, 0, 0, 0])
        let size = UInt32(payload.count + 8)
        bytes += [
            UInt8((size >> 24) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8(size & 0xff)
        ]
        bytes += Array(boxType.utf8)
        bytes += payload
        return Data(bytes)
    }

    private func makeInitializationDataWithSampleEntry(sampleEntryType: String, boxType: String, payload: [UInt8]) -> Data {
        let codecConfiguration = makeBox(boxType, payload: payload)
        let sampleEntryPayload = Array(repeating: UInt8(0), count: 78) + codecConfiguration
        let sampleEntry = makeBox(sampleEntryType, payload: sampleEntryPayload)
        let stsdPayload = [UInt8](repeating: 0, count: 4) + [0, 0, 0, 1] + sampleEntry
        let moov = makeBox(
            "moov",
            payload: makeBox(
                "trak",
                payload: makeBox(
                    "mdia",
                    payload: makeBox(
                        "minf",
                        payload: makeBox(
                            "stbl",
                            payload: makeBox("stsd", payload: stsdPayload)
                        )
                    )
                )
            )
        )
        let ftyp = makeBox("ftyp", payload: Array("isom".utf8) + [0, 0, 0, 0])
        return Data(ftyp + moov)
    }

    private func makeBox(_ type: String, payload: [UInt8]) -> [UInt8] {
        let size = UInt32(payload.count + 8)
        return [
            UInt8((size >> 24) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8(size & 0xff)
        ] + Array(type.utf8) + payload
    }

    private func makePayload(profile: Int, level: Int, compatibilityID: Int) -> [UInt8] {
        [
            1,
            0,
            UInt8((profile << 1) | ((level >> 5) & 0x01)),
            UInt8(((level & 0x1f) << 3) | 0x05),
            UInt8((compatibilityID & 0x0f) << 4)
        ]
    }
}

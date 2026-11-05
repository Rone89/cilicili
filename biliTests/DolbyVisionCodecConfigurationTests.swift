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
        XCTAssertEqual(
            configuration?.hlsAdvertisedSupplementalCodec(baseLayerCodec: "hev1.2.4.L150.b0"),
            "dvh1.08.06/db1p"
        )
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

    func testNormalizesPlainHEVCSampleEntryForHLS() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hev1",
            boxType: "hvcC",
            payload: makeHEVCPayload(profileIDC: 1, compatibilityFlags: 6, levelIDC: 150)
        )
        let normalization = DolbyVisionCodecConfiguration.normalizedHEVCInitializationDataForHLS(data)

        XCTAssertEqual(normalization.originalSampleEntryType, "hev1")
        XCTAssertEqual(normalization.hlsSampleEntryType, "hvc1")
        XCTAssertEqual(normalization.hlsBaseLayerCodec, "hvc1.1.6.L150.B0")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization.data), "hvc1")
    }

    func testHEVCCodecStringUsesHLSCompatibilityBitOrder() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hvc1",
            boxType: "hvcC",
            payload: makeHEVCPayload(
                profileIDC: 2,
                compatibilityFlags: 4,
                levelIDC: 150,
                constraintBytes: [0x90],
                tierFlag: true
            )
        )

        XCTAssertEqual(DolbyVisionCodecConfiguration.hevcCodecString(from: data), "hvc1.2.4.H150.90")
    }

    func testHDR10DynamicRangeDoesNotGuessHLSVideoRange() {
        XCTAssertNil(BiliVideoDynamicRange.hdr10.hlsVideoRangeAttribute)
        XCTAssertEqual(BiliVideoDynamicRange.hlg.hlsVideoRangeAttribute, "HLG")
        XCTAssertEqual(BiliVideoDynamicRange.dolbyVision.hlsVideoRangeAttribute, "PQ")
    }

    func testHDR10VideoRangeFallbackOnlyForAuthoritativeQualities() {
        XCTAssertEqual(HLSRendition.hlsVideoRangeFallback(dynamicRange: .hdr10, quality: 125), "PQ")
        XCTAssertEqual(HLSRendition.hlsVideoRangeFallback(dynamicRange: .hdr10, quality: 129), "PQ")
        XCTAssertNil(HLSRendition.hlsVideoRangeFallback(dynamicRange: .hdr10, quality: 120))
        XCTAssertNil(HLSRendition.hlsVideoRangeFallback(dynamicRange: .hdr10, quality: nil))
        XCTAssertEqual(HLSRendition.hlsVideoRangeFallback(dynamicRange: .hlg, quality: nil), "HLG")
        XCTAssertNil(HLSRendition.hlsVideoRangeFallback(dynamicRange: .sdr, quality: 125))
    }

    func testHDR10HEVCInitializationAddsPQColorInformation() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hev1",
            boxType: "hvcC",
            payload: makeHEVCPayload(profileIDC: 2, compatibilityFlags: 4, levelIDC: 153)
        )
        XCTAssertNil(DolbyVisionCodecConfiguration.videoColorInformation(from: data))

        let normalization = DolbyVisionCodecConfiguration.normalizedHEVCInitializationDataForHLS(
            data,
            dynamicRange: .hdr10
        )
        let color = DolbyVisionCodecConfiguration.videoColorInformation(from: normalization.data)
        XCTAssertEqual(color?.colorPrimaries, 9)
        XCTAssertEqual(color?.transferCharacteristics, 16)
        XCTAssertEqual(color?.matrixCoefficients, 9)
        XCTAssertEqual(color?.hlsVideoRangeAttribute, "PQ")
    }

    func testSDRHEVCInitializationKeepsMissingColorInformation() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hev1",
            boxType: "hvcC",
            payload: makeHEVCPayload(profileIDC: 2, compatibilityFlags: 4, levelIDC: 153)
        )
        let normalization = DolbyVisionCodecConfiguration.normalizedHEVCInitializationDataForHLS(
            data,
            dynamicRange: .sdr
        )
        XCTAssertNil(DolbyVisionCodecConfiguration.videoColorInformation(from: normalization.data))
    }

    func testParsesPQColorInformationFromInitializationData() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hvc1",
            boxType: "hvcC",
            payload: makeHEVCPayload(profileIDC: 1, compatibilityFlags: 6, levelIDC: 150),
            extraSampleEntryBoxes: [
                makeColorInformationBox(transferCharacteristics: 16)
            ]
        )
        let information = DolbyVisionCodecConfiguration.videoColorInformation(from: data)

        XCTAssertEqual(information?.colorType, "nclx")
        XCTAssertEqual(information?.colorPrimaries, 9)
        XCTAssertEqual(information?.transferCharacteristics, 16)
        XCTAssertEqual(information?.matrixCoefficients, 9)
        XCTAssertEqual(information?.fullRangeFlag, false)
        XCTAssertEqual(information?.hlsVideoRangeAttribute, "PQ")
    }

    func testParsesHLGColorInformationFromInitializationData() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hvc1",
            boxType: "hvcC",
            payload: makeHEVCPayload(profileIDC: 1, compatibilityFlags: 6, levelIDC: 150),
            extraSampleEntryBoxes: [
                makeColorInformationBox(transferCharacteristics: 18, fullRange: true)
            ]
        )
        let information = DolbyVisionCodecConfiguration.videoColorInformation(from: data)

        XCTAssertEqual(information?.transferCharacteristics, 18)
        XCTAssertEqual(information?.fullRangeFlag, true)
        XCTAssertEqual(information?.hlsVideoRangeAttribute, "HLG")
    }

    func testUnrecognizedColorTransferDoesNotAdvertiseVideoRange() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "hvc1",
            boxType: "hvcC",
            payload: makeHEVCPayload(profileIDC: 1, compatibilityFlags: 6, levelIDC: 150),
            extraSampleEntryBoxes: [
                makeColorInformationBox(transferCharacteristics: 1)
            ]
        )
        let information = DolbyVisionCodecConfiguration.videoColorInformation(from: data)

        XCTAssertEqual(information?.transferCharacteristics, 1)
        XCTAssertNil(information?.hlsVideoRangeAttribute)
    }

    func testUsesHVC1FallbackWhenDolbyConfigurationIsMissing() {
        XCTAssertEqual(
            DolbyVisionCodecConfiguration.hlsCompatibleHEVCCodec(from: "dvh1.08.06", initializationData: nil),
            "hvc1.1.6.L120.B0"
        )
        XCTAssertEqual(
            DolbyVisionCodecConfiguration.hlsCompatibleHEVCCodec(from: "hev1.2.4.L150.b0", initializationData: nil),
            "hvc1.2.4.L150.b0"
        )
    }

    func testNormalizesProfileEightDolbyVisionSampleEntryToBaseLayerForHLS() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "dvh1",
            boxType: "dvcC",
            payload: makePayload(profile: 8, level: 6, compatibilityID: 1),
            extraSampleEntryBoxes: [
                makeBox("hvcC", payload: makeHEVCPayload(profileIDC: 1, compatibilityFlags: 6, levelIDC: 150))
            ]
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(data)

        XCTAssertEqual(normalization?.originalSampleEntryType, "dvh1")
        XCTAssertEqual(normalization?.hlsSampleEntryType, "hvc1")
        XCTAssertTrue(normalization?.didRewriteSampleEntry ?? false)
        XCTAssertEqual(normalization?.hlsBaseLayerCodec, "hvc1.1.6.L150.B0")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "hvc1")
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(baseLayerCodec: normalization?.hlsBaseLayerCodec ?? ""), "hvc1.1.6.L150.B0")
        XCTAssertEqual(
            configuration?.hlsAdvertisedSupplementalCodec(baseLayerCodec: normalization?.hlsBaseLayerCodec ?? ""),
            "dvh1.08.06/db1p"
        )
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
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .fullEffect
        ), "hvc1.2.4.H150.90")
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .fullEffect
        ))
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .supplementalHLS
        ), "hvc1.2.4.H150.90")
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .supplementalHLS
        ))
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .metadataPassthrough
        ), "hvc1.2.4.H150.90")
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .metadataPassthrough
        ))
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .appleNativeP8HLS
        ), "hvc1.2.4.H150.90")
        XCTAssertEqual(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .appleNativeP8HLS
        ), "dvh1.08.07/db4h")
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: "hvc1.2.4.H150.90",
            renderingPolicy: .compatibleHLG
        ))
        XCTAssertEqual(configuration?.hlsVideoRangeAttribute, "HLG")
    }

    func testAppleNativeP8PolicyKeepsDolbyVisionMetadataAndAdvertisesSupplementalCodec() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "dvh1",
            boxType: "dvvC",
            payload: makePayload(profile: 8, level: 7, compatibilityID: 4),
            extraSampleEntryBoxes: [
                makeBox(
                    "hvcC",
                    payload: makeHEVCPayload(
                        profileIDC: 2,
                        compatibilityFlags: 4,
                        levelIDC: 150,
                        constraintBytes: [0x90],
                        tierFlag: true
                    )
                )
            ]
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(
            data,
            renderingPolicy: .appleNativeP8HLS
        )

        XCTAssertEqual(normalization?.originalSampleEntryType, "dvh1")
        XCTAssertEqual(normalization?.hlsSampleEntryType, "hvc1")
        XCTAssertEqual(normalization?.hlsBaseLayerCodec, "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "hvc1")
        XCTAssertEqual(DolbyVisionCodecConfiguration.hevcCodecString(from: normalization?.data), "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.videoColorInformation(from: normalization?.data)?.hlsVideoRangeAttribute, "HLG")
        XCTAssertEqual(DolbyVisionCodecConfiguration.parse(from: normalization?.data), configuration)
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .appleNativeP8HLS
        ), "hvc1.2.4.H150.90")
        XCTAssertEqual(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .appleNativeP8HLS
        ), "dvh1.08.07/db4h")
    }

    func testDeprecatedFullEffectPolicyNormalizesToBaseLayerOnly() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "dvh1",
            boxType: "dvvC",
            payload: makePayload(profile: 8, level: 7, compatibilityID: 4),
            extraSampleEntryBoxes: [
                makeBox(
                    "hvcC",
                    payload: makeHEVCPayload(
                        profileIDC: 2,
                        compatibilityFlags: 4,
                        levelIDC: 150,
                        constraintBytes: [0x90],
                        tierFlag: true
                    )
                )
            ]
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(
            data,
            renderingPolicy: .fullEffect
        )

        XCTAssertEqual(normalization?.originalSampleEntryType, "dvh1")
        XCTAssertEqual(normalization?.hlsSampleEntryType, "hvc1")
        XCTAssertEqual(normalization?.hlsBaseLayerCodec, "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "hvc1")
        XCTAssertEqual(DolbyVisionCodecConfiguration.hevcCodecString(from: normalization?.data), "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.videoColorInformation(from: normalization?.data)?.hlsVideoRangeAttribute, "HLG")
        XCTAssertNil(DolbyVisionCodecConfiguration.parse(from: normalization?.data))
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .fullEffect
        ), "hvc1.2.4.H150.90")
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .fullEffect
        ))
    }

    func testMetadataPassthroughPolicyNowNormalizesToBaseLayerOnly() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "dvh1",
            boxType: "dvvC",
            payload: makePayload(profile: 8, level: 7, compatibilityID: 4),
            extraSampleEntryBoxes: [
                makeBox(
                    "hvcC",
                    payload: makeHEVCPayload(
                        profileIDC: 2,
                        compatibilityFlags: 4,
                        levelIDC: 150,
                        constraintBytes: [0x90],
                        tierFlag: true
                    )
                )
            ]
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(
            data,
            renderingPolicy: .metadataPassthrough
        )

        XCTAssertEqual(normalization?.originalSampleEntryType, "dvh1")
        XCTAssertEqual(normalization?.hlsSampleEntryType, "hvc1")
        XCTAssertEqual(normalization?.hlsBaseLayerCodec, "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "hvc1")
        XCTAssertEqual(DolbyVisionCodecConfiguration.hevcCodecString(from: normalization?.data), "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.videoColorInformation(from: normalization?.data)?.hlsVideoRangeAttribute, "HLG")
        XCTAssertNil(DolbyVisionCodecConfiguration.parse(from: normalization?.data))
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .metadataPassthrough
        ), "hvc1.2.4.H150.90")
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .metadataPassthrough
        ))
    }

    func testDeprecatedDolbyPoliciesAreMigratedOutOfUserFacingChoices() {
        XCTAssertFalse(DolbyVisionRenderingPolicy.allCases.contains(.metadataPassthrough))
        XCTAssertTrue(DolbyVisionRenderingPolicy.allCases.contains(.appleNativeP8HLS))
        XCTAssertFalse(DolbyVisionRenderingPolicy.allCases.contains(.fullEffect))
        XCTAssertFalse(DolbyVisionRenderingPolicy.allCases.contains(.protectedHLG))
        XCTAssertFalse(DolbyVisionRenderingPolicy.allCases.contains(.supplementalHLS))
        XCTAssertEqual(DolbyVisionRenderingPolicy.metadataPassthrough.playablePolicy, .compatibleHLG)
        XCTAssertEqual(DolbyVisionRenderingPolicy.appleNativeP8HLS.playablePolicy, .appleNativeP8HLS)
        XCTAssertEqual(DolbyVisionRenderingPolicy.appleNativeP8HLS.hlsBridgePolicy, .compatibleHLG)
        XCTAssertEqual(DolbyVisionRenderingPolicy.fullEffect.playablePolicy, .compatibleHLG)
        XCTAssertEqual(DolbyVisionRenderingPolicy.protectedHLG.playablePolicy, .compatibleHLG)
        XCTAssertEqual(DolbyVisionRenderingPolicy.supplementalHLS.playablePolicy, .compatibleHLG)

        let suiteName = "DolbyVisionRenderingPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(DolbyVisionRenderingPolicy.fullEffect.rawValue, forKey: DolbyVisionRenderingPolicy.storageKey)

        XCTAssertEqual(DolbyVisionRenderingPolicy.stored(in: defaults), .appleNativeP8HLS)
        defaults.set(DolbyVisionRenderingPolicy.protectedHLG.rawValue, forKey: DolbyVisionRenderingPolicy.storageKey)
        XCTAssertEqual(DolbyVisionRenderingPolicy.stored(in: defaults), .appleNativeP8HLS)
        defaults.set(DolbyVisionRenderingPolicy.supplementalHLS.rawValue, forKey: DolbyVisionRenderingPolicy.storageKey)
        XCTAssertEqual(DolbyVisionRenderingPolicy.stored(in: defaults), .appleNativeP8HLS)
        defaults.set(DolbyVisionRenderingPolicy.appleNativeP8HLS.rawValue, forKey: DolbyVisionRenderingPolicy.storageKey)
        XCTAssertEqual(DolbyVisionRenderingPolicy.stored(in: defaults), .appleNativeP8HLS)
        defaults.set(DolbyVisionRenderingPolicy.metadataPassthrough.rawValue, forKey: DolbyVisionRenderingPolicy.storageKey)
        XCTAssertEqual(DolbyVisionRenderingPolicy.stored(in: defaults), .appleNativeP8HLS)
        XCTAssertEqual(defaults.string(forKey: DolbyVisionRenderingPolicy.storageKey), DolbyVisionRenderingPolicy.appleNativeP8HLS.rawValue)
    }

    func testProtectedHLGModeMigratesToBaseLayerOnly() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "dvh1",
            boxType: "dvvC",
            payload: makePayload(profile: 8, level: 7, compatibilityID: 4),
            extraSampleEntryBoxes: [
                makeBox(
                    "hvcC",
                    payload: makeHEVCPayload(
                        profileIDC: 2,
                        compatibilityFlags: 4,
                        levelIDC: 150,
                        constraintBytes: [0x90],
                        tierFlag: true
                    )
                )
            ]
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(
            data,
            renderingPolicy: .protectedHLG
        )

        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "hvc1")
        XCTAssertEqual(DolbyVisionCodecConfiguration.videoColorInformation(from: normalization?.data)?.hlsVideoRangeAttribute, "HLG")
        XCTAssertNil(DolbyVisionCodecConfiguration.parse(from: normalization?.data))
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .protectedHLG
        ))
    }

    func testNormalizesProfileEightHLGCompatibleDolbyVisionAsBaseLayerOnlyForHLS() {
        let data = makeInitializationDataWithSampleEntry(
            sampleEntryType: "dvh1",
            boxType: "dvvC",
            payload: makePayload(profile: 8, level: 7, compatibilityID: 4),
            extraSampleEntryBoxes: [
                makeBox(
                    "hvcC",
                    payload: makeHEVCPayload(
                        profileIDC: 2,
                        compatibilityFlags: 4,
                        levelIDC: 150,
                        constraintBytes: [0x90],
                        tierFlag: true
                    )
                )
            ]
        )
        let configuration = DolbyVisionCodecConfiguration.parse(from: data)
        let normalization = configuration?.normalizedInitializationDataForHLS(
            data,
            renderingPolicy: .compatibleHLG
        )

        XCTAssertEqual(normalization?.originalSampleEntryType, "dvh1")
        XCTAssertEqual(normalization?.hlsSampleEntryType, "hvc1")
        XCTAssertEqual(normalization?.hlsBaseLayerCodec, "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.sampleEntryType(in: normalization?.data), "hvc1")
        XCTAssertEqual(DolbyVisionCodecConfiguration.hevcCodecString(from: normalization?.data), "hvc1.2.4.H150.90")
        XCTAssertEqual(DolbyVisionCodecConfiguration.videoColorInformation(from: normalization?.data)?.hlsVideoRangeAttribute, "HLG")
        XCTAssertNil(DolbyVisionCodecConfiguration.parse(from: normalization?.data))
        XCTAssertEqual(configuration?.hlsAdvertisedCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .compatibleHLG
        ), "hvc1.2.4.H150.90")
        XCTAssertNil(configuration?.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: normalization?.hlsBaseLayerCodec ?? "",
            renderingPolicy: .compatibleHLG
        ))
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

    private func makeInitializationDataWithSampleEntry(
        sampleEntryType: String,
        boxType: String,
        payload: [UInt8],
        extraSampleEntryBoxes: [[UInt8]] = []
    ) -> Data {
        let codecConfiguration = makeBox(boxType, payload: payload)
        let sampleEntryPayload = Array(repeating: UInt8(0), count: 78)
            + extraSampleEntryBoxes.flatMap { $0 }
            + codecConfiguration
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

    private func makeColorInformationBox(
        transferCharacteristics: UInt16,
        fullRange: Bool = false
    ) -> [UInt8] {
        makeBox(
            "colr",
            payload: Array("nclx".utf8)
                + uint16Bytes(9)
                + uint16Bytes(transferCharacteristics)
                + uint16Bytes(9)
                + [fullRange ? 0x80 : 0x00]
        )
    }

    private func makePayload(profile: Int, level: Int, compatibilityID: Int) -> [UInt8] {
        return [
            1,
            0,
            UInt8((profile << 1) | ((level >> 5) & 0x01)),
            UInt8(((level & 0x1f) << 3) | 0x05),
            UInt8((compatibilityID & 0x0f) << 4)
        ]
    }

    private func makeHEVCPayload(
        profileIDC: UInt8,
        compatibilityFlags: UInt32,
        levelIDC: UInt8,
        constraintBytes: [UInt8] = [0xb0],
        tierFlag: Bool = false
    ) -> [UInt8] {
        let encodedCompatibilityFlags = hevcRecordCompatibilityFlags(fromHLSFlags: compatibilityFlags)
        let normalizedConstraintBytes = Array((constraintBytes + Array(repeating: 0, count: 6)).prefix(6))
        return [
            1,
            (profileIDC & 0x1f) | (tierFlag ? 0x20 : 0),
            UInt8((encodedCompatibilityFlags >> 24) & 0xff),
            UInt8((encodedCompatibilityFlags >> 16) & 0xff),
            UInt8((encodedCompatibilityFlags >> 8) & 0xff),
            UInt8(encodedCompatibilityFlags & 0xff)
        ] + normalizedConstraintBytes + [
            levelIDC
        ]
    }

    private func hevcRecordCompatibilityFlags(fromHLSFlags flags: UInt32) -> UInt32 {
        var source = flags
        var result: UInt32 = 0
        for _ in 0..<32 {
            result = (result << 1) | (source & 1)
            source >>= 1
        }
        return result
    }

    private func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }
}

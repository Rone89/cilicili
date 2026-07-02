import Foundation

struct DolbyVisionInitializationNormalization: Equatable, Sendable {
    let data: Data?
    let originalSampleEntryType: String?
    let hlsSampleEntryType: String?

    nonisolated var didRewriteSampleEntry: Bool {
        guard let originalSampleEntryType, let hlsSampleEntryType else { return false }
        return originalSampleEntryType != hlsSampleEntryType
    }
}

struct DolbyVisionCodecConfiguration: Equatable, Sendable {
    let boxType: String
    let profile: Int
    let level: Int
    let rpuPresent: Bool
    let enhancementLayerPresent: Bool
    let baseLayerPresent: Bool
    let baseLayerSignalCompatibilityID: Int

    nonisolated static func parse(from initializationData: Data?) -> DolbyVisionCodecConfiguration? {
        guard let initializationData, !initializationData.isEmpty else { return nil }
        let bytes = [UInt8](initializationData)
        guard bytes.count >= 12 else { return nil }
        for offset in 0...(bytes.count - 12) {
            guard let boxType = dolbyVisionBoxType(in: bytes, at: offset + 4),
                  let payloadRange = payloadRange(in: bytes, boxOffset: offset)
            else { continue }
            let payload = Array(bytes[payloadRange])
            if let configuration = parseRecord(payload, boxType: boxType) {
                return configuration
            }
        }
        return nil
    }

    nonisolated var decoderCodecString: String {
        "\(codecPrefix).\(Self.twoDigit(profile)).\(Self.twoDigit(level))"
    }

    nonisolated func hlsAdvertisedCodec(baseLayerCodec: String) -> String {
        guard usesSupplementalCodecsAttribute else {
            return decoderCodecString
        }
        return Self.hlsBaseLayerCodec(baseLayerCodec)
    }

    nonisolated func normalizedInitializationDataForHLS(_ initializationData: Data?) -> DolbyVisionInitializationNormalization {
        guard let initializationData, !initializationData.isEmpty else {
            return DolbyVisionInitializationNormalization(data: initializationData, originalSampleEntryType: nil, hlsSampleEntryType: nil)
        }
        var bytes = [UInt8](initializationData)
        guard let sampleEntryTypeOffset = Self.sampleEntryTypeOffset(in: bytes),
              let originalType = Self.string(in: bytes, at: sampleEntryTypeOffset),
              let hlsType = hlsSampleEntryType(for: originalType)
        else {
            return DolbyVisionInitializationNormalization(
                data: initializationData,
                originalSampleEntryType: Self.sampleEntryType(in: initializationData),
                hlsSampleEntryType: nil
            )
        }
        if hlsType != originalType {
            bytes.replaceSubrange(sampleEntryTypeOffset..<(sampleEntryTypeOffset + 4), with: Array(hlsType.utf8))
        }
        return DolbyVisionInitializationNormalization(data: Data(bytes), originalSampleEntryType: originalType, hlsSampleEntryType: hlsType)
    }

    nonisolated static func sampleEntryType(in initializationData: Data?) -> String? {
        guard let initializationData, !initializationData.isEmpty else { return nil }
        let bytes = [UInt8](initializationData)
        guard let offset = sampleEntryTypeOffset(in: bytes) else { return nil }
        return string(in: bytes, at: offset)
    }

    nonisolated var supplementalCodecString: String {
        guard let brand = hlsCompatibilityBrand else { return decoderCodecString }
        return "\(decoderCodecString)/\(brand)"
    }

    nonisolated var usesSupplementalCodecsAttribute: Bool {
        profile == 8 || (profile == 10 && baseLayerSignalCompatibilityID != 0)
    }

    nonisolated var hlsVideoRangeAttribute: String {
        switch baseLayerSignalCompatibilityID {
        case 4:
            return "HLG"
        default:
            return "PQ"
        }
    }

    nonisolated private var codecPrefix: String {
        boxType == "dvwC" ? "dav1" : "dvh1"
    }

    nonisolated private static func hlsBaseLayerCodec(_ codec: String) -> String {
        let trimmed = codec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return codec }
        let lowercased = trimmed.lowercased()
        guard lowercased == "hev1" || lowercased.hasPrefix("hev1.") else {
            return trimmed
        }
        return "hvc1" + trimmed.dropFirst(4)
    }

    nonisolated private func hlsSampleEntryType(for originalType: String) -> String? {
        switch originalType {
        case "hev1", "hvc1", "dvhe", "dvh1":
            return usesSupplementalCodecsAttribute ? "hvc1" : "dvh1"
        default:
            return nil
        }
    }

    nonisolated private var hlsCompatibilityBrand: String? {
        switch baseLayerSignalCompatibilityID {
        case 1:
            return "db1p"
        case 2:
            return "db2g"
        case 4:
            return "db4h"
        default:
            return nil
        }
    }

    nonisolated private static func parseRecord(
        _ payload: [UInt8],
        boxType: String
    ) -> DolbyVisionCodecConfiguration? {
        guard payload.count >= 4 else { return nil }
        let profile = Int(payload[2] >> 1)
        let level = Int(((payload[2] & 0x01) << 5) | (payload[3] >> 3))
        guard profile > 0, level > 0 else { return nil }
        return DolbyVisionCodecConfiguration(
            boxType: boxType,
            profile: profile,
            level: level,
            rpuPresent: (payload[3] & 0x04) != 0,
            enhancementLayerPresent: (payload[3] & 0x02) != 0,
            baseLayerPresent: (payload[3] & 0x01) != 0,
            baseLayerSignalCompatibilityID: payload.count >= 5 ? Int(payload[4] >> 4) : 0
        )
    }

    nonisolated private static func dolbyVisionBoxType(in bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let type = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
        return type == "dvcC" || type == "dvvC" || type == "dvwC" ? type : nil
    }

    nonisolated private static func sampleEntryTypeOffset(in bytes: [UInt8]) -> Int? {
        sampleEntryTypeOffset(in: bytes, range: 0..<bytes.count)
    }

    nonisolated private static func sampleEntryTypeOffset(in bytes: [UInt8], range: Range<Int>) -> Int? {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            guard let box = boxInfo(in: bytes, at: offset, upperBound: range.upperBound) else { return nil }
            if box.type == "stsd" {
                return sampleEntryTypeOffsetInSTSD(in: bytes, payloadRange: box.payloadRange)
            }
            if isContainerBox(box.type),
               let nestedOffset = sampleEntryTypeOffset(in: bytes, range: box.payloadRange) {
                return nestedOffset
            }
            offset = box.boxRange.upperBound
        }
        return nil
    }

    nonisolated private static func sampleEntryTypeOffsetInSTSD(in bytes: [UInt8], payloadRange: Range<Int>) -> Int? {
        guard payloadRange.lowerBound + 16 <= payloadRange.upperBound else { return nil }
        let entryCount = readUInt32(in: bytes, at: payloadRange.lowerBound + 4)
        guard entryCount > 0 else { return nil }
        let entryOffset = payloadRange.lowerBound + 8
        let entrySize = Int(readUInt32(in: bytes, at: entryOffset))
        guard entrySize >= 8,
              entryOffset + entrySize <= payloadRange.upperBound
        else { return nil }
        return entryOffset + 4
    }

    nonisolated private static func payloadRange(in bytes: [UInt8], boxOffset: Int) -> Range<Int>? {
        boxInfo(in: bytes, at: boxOffset, upperBound: bytes.count)?.payloadRange
    }

    nonisolated private static func boxInfo(
        in bytes: [UInt8],
        at boxOffset: Int,
        upperBound: Int
    ) -> (type: String, payloadRange: Range<Int>, boxRange: Range<Int>)? {
        guard boxOffset >= 0, boxOffset + 8 <= bytes.count else { return nil }
        guard upperBound <= bytes.count, boxOffset + 8 <= upperBound else { return nil }
        let size32 = readUInt32(in: bytes, at: boxOffset)
        let headerSize: Int
        let boxSize: Int
        if size32 == 1 {
            guard boxOffset + 16 <= bytes.count,
                  let largeSize = Int(exactly: readUInt64(in: bytes, at: boxOffset + 8))
            else { return nil }
            headerSize = 16
            boxSize = largeSize
        } else if size32 == 0 {
            headerSize = 8
            boxSize = bytes.count - boxOffset
        } else {
            headerSize = 8
            boxSize = Int(size32)
        }
        guard boxSize >= headerSize,
              boxOffset + boxSize <= upperBound,
              let type = string(in: bytes, at: boxOffset + 4)
        else { return nil }
        return (type, (boxOffset + headerSize)..<(boxOffset + boxSize), boxOffset..<(boxOffset + boxSize))
    }

    nonisolated private static func isContainerBox(_ type: String) -> Bool {
        switch type {
        case "moov", "trak", "mdia", "minf", "stbl":
            return true
        default:
            return false
        }
    }

    nonisolated private static func string(in bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
    }

    nonisolated private static func readUInt32(in bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    nonisolated private static func readUInt64(in bytes: [UInt8], at offset: Int) -> UInt64 {
        bytes[offset..<(offset + 8)].reduce(UInt64(0)) { result, byte in
            (result << 8) | UInt64(byte)
        }
    }

    nonisolated private static func twoDigit(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

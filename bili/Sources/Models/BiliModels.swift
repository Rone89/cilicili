import CoreGraphics
import Foundation

enum BiliVideoDynamicRange: String, Hashable, Sendable {
    case sdr
    case hdr10
    case hlg
    case dolbyVision

    nonisolated var isHDR: Bool {
        self != .sdr
    }

    nonisolated var hlsVideoRangeAttribute: String? {
        switch self {
        case .sdr:
            return nil
        case .hdr10, .dolbyVision:
            return "PQ"
        case .hlg:
            return "HLG"
        }
    }
}

struct BiliResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let msg: String?
    let data: T?
    let result: T?

    var payload: T? {
        data ?? result
    }

    var displayMessage: String? {
        message ?? msg
    }
}

struct BiliPage<T: Decodable>: Decodable {
    let list: [T]?
    let item: [T]?
    let result: [T]?
}

struct VideoItem: Identifiable, Decodable, Hashable {
    var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let owner: VideoOwner?
    let stat: VideoStat?
    let cid: Int?
    let pages: [VideoPage]?
    let dimension: VideoDimension?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, title, pic, desc, duration, pubdate, owner, stat, cid, pages, dimension
    }

    func mergingFilledValues(from fullDetail: VideoItem) -> VideoItem {
        VideoItem(
            bvid: fullDetail.bvid.isEmpty ? bvid : fullDetail.bvid,
            aid: fullDetail.aid ?? aid,
            title: fullDetail.title.isEmpty ? title : fullDetail.title,
            pic: fullDetail.pic ?? pic,
            desc: fullDetail.desc ?? desc,
            duration: fullDetail.duration ?? duration,
            pubdate: fullDetail.pubdate ?? pubdate,
            owner: fullDetail.owner ?? owner,
            stat: fullDetail.stat ?? stat,
            cid: cid ?? fullDetail.cid,
            pages: fullDetail.pages ?? pages,
            dimension: fullDetail.dimension ?? dimension
        )
    }
}

struct VideoOwner: Decodable, Hashable {
    let mid: Int
    let name: String
    let face: String?

    enum CodingKeys: String, CodingKey {
        case mid, name, face, avatar
        case faceURL = "face_url"
    }

    init(mid: Int, name: String, face: String?) {
        self.mid = mid
        self.name = name
        self.face = face
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        face = try container.decodeIfPresent(String.self, forKey: .face)
            ?? container.decodeIfPresent(String.self, forKey: .avatar)
            ?? container.decodeIfPresent(String.self, forKey: .faceURL)
    }
}

struct VideoStat: Decodable, Hashable {
    let view: Int?
    let reply: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?
}

struct VideoPage: Identifiable, Decodable, Hashable {
    var id: Int { cid }

    let cid: Int
    let page: Int?
    let part: String?
    let duration: Int?
    let dimension: VideoDimension?
}

struct VideoDimension: Decodable, Hashable {
    let width: Int?
    let height: Int?
    let rotate: Int?

    var aspectRatio: Double? {
        guard var width, var height, width > 0, height > 0 else { return nil }
        if abs(rotate ?? 0) == 90 || abs(rotate ?? 0) == 270 {
            swap(&width, &height)
        }
        return Double(width) / Double(height)
    }
}

struct UploaderProfile: Decodable, Hashable {
    let card: UploaderCard?
    let follower: Int?
    let following: Bool?
    let likeNum: Int?
    let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case card, follower, following
        case likeNum = "like_num"
        case archiveCount = "archive_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try container.decodeIfPresent(UploaderCard.self, forKey: .card)
        follower = container.decodeLossyIntIfPresent(forKey: .follower)
        following = container.decodeLossyBoolIfPresent(forKey: .following)
        likeNum = container.decodeLossyIntIfPresent(forKey: .likeNum)
        archiveCount = container.decodeLossyIntIfPresent(forKey: .archiveCount)
    }
}

struct UploaderCard: Decodable, Hashable {
    let mid: Int?
    let name: String?
    let face: String?
    let sign: String?
    let fans: Int?
    let attention: Int?

    enum CodingKeys: String, CodingKey {
        case mid, name, face, sign, fans, attention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        sign = try container.decodeIfPresent(String.self, forKey: .sign)
        fans = container.decodeLossyIntIfPresent(forKey: .fans)
        attention = container.decodeLossyIntIfPresent(forKey: .attention)
    }
}

struct UploaderVideoData: Decodable {
    let list: UploaderVideoList?
}

struct UploaderVideoList: Decodable {
    let vlist: [UploaderVideoItem]?
}

struct UploaderVideoItem: Decodable, Hashable {
    let bvid: String
    let aid: Int?
    let author: String?
    let mid: Int?
    let title: String
    let pic: String?
    let description: String?
    let length: String?
    let play: Int?
    let comment: Int?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, author, mid, title, pic, description, length, play, comment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid) ?? ""
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        length = try container.decodeIfPresent(String.self, forKey: .length)
        play = container.decodeLossyIntIfPresent(forKey: .play)
        comment = container.decodeLossyIntIfPresent(forKey: .comment)
    }

    func asVideoItem(defaultMID: Int) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic?.normalizedBiliURL(),
            desc: description,
            duration: length.flatMap(Self.durationSeconds),
            pubdate: nil,
            owner: VideoOwner(mid: mid ?? defaultMID, name: author ?? "", face: nil),
            stat: VideoStat(view: play, reply: comment, like: nil, coin: nil, favorite: nil),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated private static func durationSeconds(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return 0
    }
}

struct RecommendFeedData: Decodable {
    let item: [RecommendFeedItem]?
}

struct RecommendFeedItem: Identifiable, Decodable, Hashable {
    var id: String { bvid ?? String(aid ?? 0) }

    let idValue: Int?
    let aid: Int?
    let bvid: String?
    let cid: Int?
    let title: String?
    let pic: String?
    let cover: String?
    let goto: String?
    let duration: Int?
    let pubdate: Int?
    let owner: VideoOwner?
    let ownerInfo: VideoOwner?
    let stat: VideoStat?
    let dimension: VideoDimension?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, cid, title, pic, cover, goto, duration, pubdate, ctime, owner, stat, dimension
        case idValue = "id"
        case ownerInfo = "owner_info"
        case pubDate = "pub_date"
        case publishTime = "publish_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idValue = container.decodeLossyIntIfPresent(forKey: .idValue)
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid)
        cid = container.decodeLossyIntIfPresent(forKey: .cid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        goto = try container.decodeIfPresent(String.self, forKey: .goto)
        duration = container.decodeLossyIntIfPresent(forKey: .duration)
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
            ?? container.decodeLossyIntIfPresent(forKey: .pubDate)
            ?? container.decodeLossyIntIfPresent(forKey: .publishTime)
            ?? container.decodeLossyIntIfPresent(forKey: .ctime)
        owner = try container.decodeIfPresent(VideoOwner.self, forKey: .owner)
        ownerInfo = try container.decodeIfPresent(VideoOwner.self, forKey: .ownerInfo)
        stat = try container.decodeIfPresent(VideoStat.self, forKey: .stat)
        dimension = try container.decodeIfPresent(VideoDimension.self, forKey: .dimension)
    }

    func asVideoItem() -> VideoItem? {
        guard goto == nil || goto == "av" else { return nil }
        guard let bvid, let title else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: idValue ?? aid,
            title: title,
            pic: pic ?? cover,
            desc: nil,
            duration: duration,
            pubdate: pubdate,
            owner: owner ?? ownerInfo,
            stat: stat,
            cid: cid,
            pages: nil,
            dimension: dimension
        )
    }
}

struct PlayURLData: Decodable, Sendable {
    let code: Int?
    let message: String?
    let durl: [PlayDURL]?
    let dash: DASHInfo?
    let quality: Int?
    let acceptQuality: [Int]?
    let acceptDescription: [String]?
    let supportFormats: [PlaySupportFormat]?

    enum CodingKeys: String, CodingKey {
        case code, message, durl, dash, quality
        case acceptQuality = "accept_quality"
        case acceptDescription = "accept_description"
        case supportFormats = "support_formats"
    }

    nonisolated func mergingDisplayFormats(from metadata: PlayURLData) -> PlayURLData {
        PlayURLData(
            code: code,
            message: message,
            durl: durl,
            dash: dash,
            quality: quality,
            acceptQuality: mergedQualities(primary: acceptQuality, secondary: metadata.acceptQuality),
            acceptDescription: mergedDescriptions(metadata: metadata),
            supportFormats: mergedSupportFormats(primary: supportFormats, secondary: metadata.supportFormats)
        )
    }

    nonisolated func mergingPlayableStreams(from other: PlayURLData) -> PlayURLData {
        let mergedDURL = durl ?? other.durl
        return PlayURLData(
            code: code ?? other.code,
            message: message ?? other.message,
            durl: mergedDURL,
            dash: dash?.mergingStreams(from: other.dash) ?? other.dash,
            quality: durl == nil && other.durl != nil ? (other.quality ?? quality) : (quality ?? other.quality),
            acceptQuality: mergedQualities(primary: acceptQuality, secondary: other.acceptQuality),
            acceptDescription: mergedDescriptions(metadata: other),
            supportFormats: mergedSupportFormats(primary: supportFormats, secondary: other.supportFormats)
        )
    }

    nonisolated var hasPlayableStreamPayload: Bool {
        durl?.contains(where: { !$0.url.isEmpty || $0.backupURL?.isEmpty == false }) == true
            || dash?.video?.isEmpty == false
    }

    nonisolated var highestPlayableQuality: Int {
        playVariants
            .filter(\.isPlayable)
            .map(\.quality)
            .max() ?? 0
    }

    nonisolated func hasPlayableQuality(_ quality: Int) -> Bool {
        playVariants.contains { $0.isPlayable && $0.quality == quality }
    }

    nonisolated func shouldRefetchForPreferredQuality(_ quality: Int) -> Bool {
        let playableVariants = playVariants.filter(\.isPlayable)
        guard !playableVariants.isEmpty else { return false }
        guard !hasPlayableQuality(quality) else { return false }
        let advertisedQualities = Set(
            (acceptQuality ?? [])
                + (supportFormats ?? []).compactMap(\.quality)
                + (dash?.video ?? []).compactMap(\.id)
                + [self.quality].compactMap { $0 }
        )
        return advertisedQualities.isEmpty || advertisedQualities.contains(quality)
    }

    nonisolated var playVariants: [PlayVariant] {
        let bestAudio = dash?.bestAudioStream
        let videosByQuality = Dictionary(grouping: dash?.video ?? [], by: { $0.id ?? 0 })
        let descriptions = Dictionary(uniqueKeysWithValues: zip(acceptQuality ?? [], acceptDescription ?? []))
        let supportByQuality = (supportFormats ?? []).reduce(into: [Int: PlaySupportFormat]()) { result, format in
            guard let quality = format.quality, result[quality] == nil else { return }
            result[quality] = format
        }
        let durlQuality = quality ?? acceptQuality?.first
        let durlURL = durl?.first?.playURL
        var orderedQualities = [Int]()
        var variants: [PlayVariant] = []

        func appendQuality(_ quality: Int?) {
            guard let quality, !orderedQualities.contains(quality) else { return }
            orderedQualities.append(quality)
        }

        supportFormats?.forEach { appendQuality($0.quality) }
        acceptQuality?.forEach { appendQuality($0) }
        dash?.video?.forEach { appendQuality($0.id) }
        if orderedQualities.isEmpty {
            appendQuality(quality)
        }

        for quality in orderedQualities {
            let support = supportByQuality[quality]
            let stream = videosByQuality[quality]?.sorted(by: DASHStream.preferPlayable).first
            let streamURL = stream?.playURL
            let progressiveURL = quality == durlQuality ? durlURL : nil
            let usesProgressiveStream = progressiveURL != nil
                && Self.prefersProgressiveFastStart(quality: quality, hasAudioStream: bestAudio?.playURL != nil)
            let selectedStream = usesProgressiveStream ? nil : stream
            let hasSelectedStream: Bool
            if case .some = selectedStream {
                hasSelectedStream = true
            } else {
                hasSelectedStream = false
            }
            variants.append(PlayVariant(
                quality: quality,
                title: support?.title ?? descriptions[quality] ?? Self.qualityTitle(quality),
                videoURL: usesProgressiveStream ? progressiveURL : (streamURL ?? progressiveURL),
                audioURL: hasSelectedStream ? bestAudio?.playURL : nil,
                videoStream: selectedStream,
                audioStream: hasSelectedStream ? bestAudio : nil,
                codec: stream?.codecLabel ?? support?.codecLabel,
                resolution: stream?.resolutionLabel,
                frameRate: stream?.frameRate,
                bandwidth: stream?.bandwidth,
                isHDR: Self.isHDR(quality: quality, title: support?.title ?? descriptions[quality]),
                badge: support?.badge
            ))
        }

        for stream in dash?.video ?? [] where !variants.contains(where: { $0.quality == (stream.id ?? 0) }) {
            let quality = stream.id ?? 0
            let support = supportByQuality[quality]
            variants.append(PlayVariant(
                quality: quality,
                title: support?.title ?? descriptions[quality] ?? Self.qualityTitle(quality),
                videoURL: stream.playURL,
                audioURL: bestAudio?.playURL,
                videoStream: stream,
                audioStream: bestAudio,
                codec: stream.codecLabel ?? support?.codecLabel,
                resolution: stream.resolutionLabel,
                frameRate: stream.frameRate,
                bandwidth: stream.bandwidth,
                isHDR: Self.isHDR(quality: quality, title: support?.title ?? descriptions[quality]),
                badge: support?.badge
            ))
        }

        if variants.isEmpty, let url = durl?.first?.playURL {
            variants.append(PlayVariant(
                quality: quality ?? 0,
                title: descriptions[quality ?? 0] ?? Self.qualityTitle(quality ?? 0),
                videoURL: url,
                audioURL: nil,
                videoStream: nil,
                audioStream: nil,
                codec: nil,
                resolution: nil,
                frameRate: nil,
                bandwidth: nil,
                isHDR: false,
                badge: nil
            ))
        }

        return variants
    }

    nonisolated private static func prefersProgressiveFastStart(quality: Int, hasAudioStream: Bool) -> Bool {
        quality <= 64 || !hasAudioStream
    }

    nonisolated private static func qualityTitle(_ quality: Int) -> String {
        switch quality {
        case 127:
            return "超高清 8K"
        case 126:
            return "杜比视界"
        case 125:
            return "真彩 HDR"
        case 120:
            return "超清 4K"
        case 116:
            return "高清 1080P 高帧率"
        case 112:
            return "高清 1080P 高码率"
        case 80:
            return "高清 1080P"
        case 74:
            return "高清 720P 高帧率"
        case 64:
            return "高清 720P"
        case 32:
            return "清晰 480P"
        case 16:
            return "流畅 360P"
        case 6:
            return "极速 240P"
        default:
            return "清晰度 \(quality)"
        }
    }

    nonisolated private static func isHDR(quality: Int, title: String?) -> Bool {
        quality == 125
            || quality == 126
            || title?.localizedCaseInsensitiveContains("HDR") == true
            || title?.contains("杜比视界") == true
    }

    nonisolated private func mergedQualities(primary: [Int]?, secondary: [Int]?) -> [Int]? {
        var result = [Int]()
        func append(_ quality: Int) {
            guard !result.contains(quality) else { return }
            result.append(quality)
        }
        secondary?.forEach(append)
        primary?.forEach(append)
        return result.isEmpty ? nil : result
    }

    nonisolated private func mergedDescriptions(metadata: PlayURLData) -> [String]? {
        let primary = Dictionary(uniqueKeysWithValues: zip(acceptQuality ?? [], acceptDescription ?? []))
        let secondary = Dictionary(uniqueKeysWithValues: zip(metadata.acceptQuality ?? [], metadata.acceptDescription ?? []))
        guard let qualities = mergedQualities(primary: acceptQuality, secondary: metadata.acceptQuality) else {
            return acceptDescription ?? metadata.acceptDescription
        }
        return qualities.map { primary[$0] ?? secondary[$0] ?? Self.qualityTitle($0) }
    }

    nonisolated private func mergedSupportFormats(primary: [PlaySupportFormat]?, secondary: [PlaySupportFormat]?) -> [PlaySupportFormat]? {
        var result = [PlaySupportFormat]()
        func append(_ format: PlaySupportFormat) {
            guard let quality = format.quality, !result.contains(where: { $0.quality == quality }) else { return }
            result.append(format)
        }
        secondary?.forEach(append)
        primary?.forEach(append)
        return result.isEmpty ? nil : result
    }
}

struct PlayVariant: Identifiable, Hashable, Sendable {
    var id: String {
        "\(quality)-\(videoURL?.absoluteString ?? "locked")"
    }

    let quality: Int
    let title: String
    let videoURL: URL?
    let audioURL: URL?
    let videoStream: DASHStream?
    let audioStream: DASHStream?
    let codec: String?
    let resolution: String?
    let frameRate: String?
    let bandwidth: Int?
    let isHDR: Bool
    let badge: String?

    nonisolated var dynamicRange: BiliVideoDynamicRange {
        if quality == 126 || title.contains("杜比视界") {
            return .dolbyVision
        }
        if title.localizedCaseInsensitiveContains("HLG") || badge?.localizedCaseInsensitiveContains("HLG") == true {
            return .hlg
        }
        return isHDR ? .hdr10 : .sdr
    }

    nonisolated var isPlayable: Bool {
        videoURL != nil && isHardwareDecodingCompatible
    }

    nonisolated var isHardwareDecodingCompatible: Bool {
        if let videoStream {
            guard videoStream.isHardwareDecodingCompatibleVideo else { return false }
        } else if audioURL != nil {
            return false
        }

        if let audioStream {
            guard audioStream.isHardwareDecodingCompatibleAudio else { return false }
        }

        return videoURL != nil
    }

    nonisolated var isProgressiveFastStart: Bool {
        guard isPlayable, audioURL == nil else { return false }
        guard case nil = videoStream else { return false }
        return true
    }

    nonisolated var videoAspectRatio: Double? {
        guard let resolution else { return nil }
        let parts = resolution
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0
        else {
            return nil
        }
        return width / height
    }

    nonisolated var isPortraitVideo: Bool {
        guard let videoAspectRatio else { return false }
        return videoAspectRatio < 0.9
    }

    nonisolated var qualityBadge: String? {
        if quality == 126 {
            return "杜比"
        }
        if isHDR {
            return "HDR"
        }
        if let badge, !badge.isEmpty {
            return badge
        }
        return nil
    }

    nonisolated var subtitle: String {
        var parts = [String]()
        if let resolution {
            parts.append(resolution)
        }
        if let frameRateLabel {
            parts.append(frameRateLabel)
        }
        if let bitrateLabel {
            parts.append(bitrateLabel)
        }
        if let codec {
            parts.append(codec)
        }
        if isHDR {
            parts.append("HDR")
        }
        if let badge, !badge.isEmpty, !parts.contains(badge) {
            parts.append(badge)
        }
        if !isPlayable {
            parts.append("需要登录或权限")
        }
        return parts.joined(separator: " · ")
    }

    nonisolated private var frameRateLabel: String? {
        if let displayFrameRate = DASHStream.displayFrameRate(from: frameRate) {
            return "\(displayFrameRate)fps"
        }
        if [116, 74].contains(quality) {
            return "60fps"
        }
        if title.contains("高帧") || title.contains("60") || badge?.contains("高帧") == true || badge?.contains("60") == true {
            return "60fps"
        }
        return nil
    }

    nonisolated private var bitrateLabel: String? {
        guard let bandwidth, bandwidth > 0 else { return nil }
        if bandwidth >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000)
        }
        return "\(Int((Double(bandwidth) / 1_000).rounded())) kbps"
    }
}

struct PlaySupportFormat: Decodable, Sendable {
    let quality: Int?
    let format: String?
    let newDescription: String?
    let displayDescription: String?
    let legacyDescription: String?
    let superscript: String?
    let codecs: [String]?

    enum CodingKeys: String, CodingKey {
        case quality, format, superscript, codecs
        case newDescription = "new_description"
        case displayDescription = "display_desc"
        case legacyDescription = "description"
    }

    nonisolated var title: String? {
        for value in [newDescription, legacyDescription, displayDescription] {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated var badge: String? {
        guard let superscript, !superscript.isEmpty else { return nil }
        return superscript
    }

    nonisolated var codecLabel: String? {
        guard let codecs, !codecs.isEmpty else { return nil }
        var labels = [String]()
        for codec in codecs {
            guard let label = DASHStream.codecLabel(for: codec), !labels.contains(label) else { continue }
            labels.append(label)
        }
        return labels.isEmpty ? nil : labels.joined(separator: "/")
    }
}

struct PlayDURL: Decodable, Sendable {
    let url: String
    let backupURL: [String]?

    enum CodingKeys: String, CodingKey {
        case url
        case backupURL = "backup_url"
    }

    nonisolated var playURL: URL? {
        URL(string: url) ?? backupURL?.compactMap(URL.init(string:)).first
    }
}

struct DASHInfo: Decodable, Sendable {
    let duration: Int?
    let video: [DASHStream]?
    let audio: [DASHStream]?

    nonisolated var bestAudioStream: DASHStream? {
        audio?
            .sorted { ($0.bandwidth ?? 0) > ($1.bandwidth ?? 0) }
            .first
    }

    nonisolated func mergingStreams(from other: DASHInfo?) -> DASHInfo {
        DASHInfo(
            duration: duration ?? other?.duration,
            video: Self.mergedStreams(primary: video, secondary: other?.video),
            audio: Self.mergedStreams(primary: audio, secondary: other?.audio)
        )
    }

    nonisolated private static func mergedStreams(primary: [DASHStream]?, secondary: [DASHStream]?) -> [DASHStream]? {
        var result = primary ?? []
        let existingKeys = Set(result.map(Self.streamKey))

        var seenKeys = existingKeys
        for stream in secondary ?? [] {
            let key = Self.streamKey(stream)
            guard seenKeys.insert(key).inserted else { continue }
            result.append(stream)
        }

        return result.isEmpty ? nil : result
    }

    nonisolated private static func streamKey(_ stream: DASHStream) -> String {
        [
            String(stream.id ?? 0),
            stream.codecs ?? "",
            stream.mimeType ?? "",
            stream.baseURL
        ].joined(separator: "|")
    }
}

struct DASHStream: Decodable, Hashable, Sendable {
    let id: Int?
    let baseURL: String
    let backupURL: [String]?
    let bandwidth: Int?
    let codecs: String?
    let codecid: Int?
    let width: Int?
    let height: Int?
    let frameRate: String?
    let mimeType: String?
    let segmentBase: DASHSegmentBase?

    enum CodingKeys: String, CodingKey {
        case id, bandwidth, codecs, codecid, width, height
        case mimeType = "mimeType"
        case mimeTypeAlt = "mime_type"
        case baseURL = "baseUrl"
        case baseURLAlt = "base_url"
        case backupURL = "backupUrl"
        case backupURLAlt = "backup_url"
        case frameRate
        case frameRateAlt = "frame_rate"
        case segmentBase = "SegmentBase"
        case segmentBaseAlt = "segment_base"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
            ?? container.decodeIfPresent(String.self, forKey: .baseURLAlt)
            ?? ""
        backupURL = try container.decodeIfPresent([String].self, forKey: .backupURL)
            ?? container.decodeIfPresent([String].self, forKey: .backupURLAlt)
        bandwidth = container.decodeLossyIntIfPresent(forKey: .bandwidth)
        codecs = try container.decodeIfPresent(String.self, forKey: .codecs)
        codecid = container.decodeLossyIntIfPresent(forKey: .codecid)
        width = container.decodeLossyIntIfPresent(forKey: .width)
        height = container.decodeLossyIntIfPresent(forKey: .height)
        frameRate = container.decodeLossyStringIfPresent(forKey: .frameRate)
            ?? container.decodeLossyStringIfPresent(forKey: .frameRateAlt)
        mimeType = container.decodeLossyStringIfPresent(forKey: .mimeType)
            ?? container.decodeLossyStringIfPresent(forKey: .mimeTypeAlt)
        segmentBase = try container.decodeIfPresent(DASHSegmentBase.self, forKey: .segmentBase)
            ?? container.decodeIfPresent(DASHSegmentBase.self, forKey: .segmentBaseAlt)
    }

    nonisolated var playURL: URL? {
        URL(string: baseURL)
    }

    nonisolated var backupPlayURLs: [URL] {
        backupURL?.compactMap(URL.init(string:)) ?? []
    }

    nonisolated var codecLabel: String? {
        Self.codecLabel(for: codecs, codecid: codecid)
    }

    nonisolated static func codecLabel(for codecs: String?, codecid: Int? = nil) -> String? {
        if let codecs, !codecs.isEmpty {
            if codecs.localizedCaseInsensitiveContains("hev") || codecs.localizedCaseInsensitiveContains("hvc") {
                return "HEVC"
            }
            if codecs.localizedCaseInsensitiveContains("av01") {
                return "AV1"
            }
            if codecs.localizedCaseInsensitiveContains("avc") {
                return "AVC"
            }
            return codecs
        }
        switch codecid {
        case 7:
            return "AVC"
        case 12:
            return "HEVC"
        case 13:
            return "AV1"
        default:
            return nil
        }
    }

    nonisolated var resolutionLabel: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)x\(height)"
    }

    nonisolated var hlsDimensions: CGSize? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    nonisolated var displayFrameRate: String? {
        Self.displayFrameRate(from: frameRate)
    }

    nonisolated var isHardwareDecodingCompatibleVideo: Bool {
        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            if lowered.contains("av01") { return false }
            return lowered.contains("avc1")
                || lowered.contains("avc3")
                || lowered.contains("hvc1")
                || lowered.contains("hev1")
                || lowered.contains("dvh1")
                || lowered.contains("dvhe")
        }

        switch codecid {
        case 7, 12:
            return true
        default:
            return false
        }
    }

    nonisolated var isHardwareDecodingCompatibleAudio: Bool {
        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("mp4a")
                || lowered.contains("alac")
                || lowered.contains("ac-3")
                || lowered.contains("ec-3")
        }
        return true
    }

    nonisolated static func displayFrameRate(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = Double(trimmed) {
            return formatFrameRate(value)
        }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2,
           let numerator = Double(parts[0]),
           let denominator = Double(parts[1]),
           denominator != 0 {
            return formatFrameRate(numerator / denominator)
        }

        return trimmed
    }

    nonisolated static func preferPlayable(_ lhs: DASHStream, _ rhs: DASHStream) -> Bool {
        if lhs.isHardwareDecodingCompatibleVideo != rhs.isHardwareDecodingCompatibleVideo {
            return lhs.isHardwareDecodingCompatibleVideo && !rhs.isHardwareDecodingCompatibleVideo
        }
        return codecRank(lhs) != codecRank(rhs)
            ? codecRank(lhs) > codecRank(rhs)
            : (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
    }

    nonisolated private static func codecRank(_ stream: DASHStream) -> Int {
        if let codecs = stream.codecs?.lowercased() {
            if codecs.contains("hvc1") || codecs.contains("hev1") {
                return 4
            }
            if codecs.contains("dvh1") || codecs.contains("dvhe") {
                return 4
            }
            if codecs.contains("avc1") || codecs.contains("avc3") {
                return 3
            }
            if codecs.contains("av01") {
                return 1
            }
        }
        switch stream.codecid {
        case 12:
            return 4
        case 7:
            return 3
        case 13:
            return 1
        default:
            return 0
        }
    }

    nonisolated private static func formatFrameRate(_ value: Double) -> String {
        let roundedValue = value.rounded()
        if abs(roundedValue - value) < 0.05 {
            return String(Int(roundedValue))
        }
        return String(format: "%.1f", value)
    }
}

struct DASHSegmentBase: Decodable, Hashable, Sendable {
    let initialization: String?
    let indexRange: String?

    enum CodingKeys: String, CodingKey {
        case initialization
        case initializationAlt = "Initialization"
        case indexRange = "indexRange"
        case indexRangeAlt = "index_range"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        initialization = container.decodeLossyStringIfPresent(forKey: .initialization)
            ?? container.decodeLossyStringIfPresent(forKey: .initializationAlt)
        indexRange = container.decodeLossyStringIfPresent(forKey: .indexRange)
            ?? container.decodeLossyStringIfPresent(forKey: .indexRangeAlt)
    }

    nonisolated var initializationByteRange: HTTPByteRange? {
        HTTPByteRange(rawValue: initialization)
    }

    nonisolated var indexByteRange: HTTPByteRange? {
        HTTPByteRange(rawValue: indexRange)
    }
}

struct HTTPByteRange: Hashable, Sendable {
    let start: Int64
    let endInclusive: Int64

    nonisolated var length: Int64 {
        max(endInclusive - start + 1, 0)
    }

    nonisolated init(start: Int64, endInclusive: Int64) {
        self.start = start
        self.endInclusive = endInclusive
    }

    nonisolated init?(httpHeaderValue: String?) {
        guard let httpHeaderValue else { return nil }
        let normalizedValue = httpHeaderValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedValue.hasPrefix("bytes=") else { return nil }
        self.init(rawValue: String(normalizedValue.dropFirst("bytes=".count)))
    }

    nonisolated init?(rawValue: String?) {
        guard let rawValue else { return nil }
        let parts = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let start = Int64(parts[0]),
              let end = Int64(parts[1]),
              start >= 0,
              end >= start
        else { return nil }
        self.start = start
        self.endInclusive = end
    }

    nonisolated func clamped(toLength length: Int64) -> HTTPByteRange? {
        guard length > 0 else { return nil }
        let lowerBound = min(max(start, 0), length - 1)
        let upperBound = min(max(endInclusive, lowerBound), length - 1)
        return HTTPByteRange(start: lowerBound, endInclusive: upperBound)
    }
}

struct CommentPage: Decodable {
    let replies: [Comment]?
    let topReplies: [Comment]?
    let cursor: CommentCursor?

    enum CodingKeys: String, CodingKey {
        case replies, cursor
        case topReplies = "top_replies"
    }
}

struct CommentCursor: Decodable {
    let next: String?
    let isEnd: Bool?

    enum CodingKeys: String, CodingKey {
        case next
        case isEnd = "is_end"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        next = container.decodeLossyStringIfPresent(forKey: .next)
        isEnd = container.decodeLossyBoolIfPresent(forKey: .isEnd)
    }
}

struct Comment: Identifiable, Decodable, Hashable {
    let rpid: Int
    let rootID: Int?
    let parentID: Int?
    let dialogID: Int?
    let member: CommentMember?
    let content: CommentContent?
    let like: Int?
    let ctime: Int?
    let replies: [Comment]?
    let replyCount: Int?
    let likeState: Int?

    var id: Int { rpid }

    var containsGoodsPromotion: Bool {
        content?.containsGoodsPromotion == true
            || replies?.contains(where: \.containsGoodsPromotion) == true
    }

    enum CodingKeys: String, CodingKey {
        case rpid, member, content, like, ctime, replies
        case rootID = "root"
        case parentID = "parent"
        case dialogID = "dialog"
        case replyCount = "rcount"
        case likeState = "like_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rpid = container.decodeLossyIntIfPresent(forKey: .rpid) ?? 0
        rootID = container.decodeLossyIntIfPresent(forKey: .rootID)
        parentID = container.decodeLossyIntIfPresent(forKey: .parentID)
        dialogID = container.decodeLossyIntIfPresent(forKey: .dialogID)
        member = try container.decodeIfPresent(CommentMember.self, forKey: .member)
        content = try container.decodeIfPresent(CommentContent.self, forKey: .content)
        like = container.decodeLossyIntIfPresent(forKey: .like)
        ctime = container.decodeLossyIntIfPresent(forKey: .ctime)
        replies = try container.decodeIfPresent([Comment].self, forKey: .replies)
        replyCount = container.decodeLossyIntIfPresent(forKey: .replyCount)
        likeState = container.decodeLossyIntIfPresent(forKey: .likeState)
    }
}

struct CommentMember: Decodable, Hashable {
    let mid: String?
    let uname: String?
    let avatar: String?
    let levelInfo: CommentLevelInfo?

    enum CodingKeys: String, CodingKey {
        case mid, uname, avatar
        case levelInfo = "level_info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyStringIfPresent(forKey: .mid)
        uname = try container.decodeIfPresent(String.self, forKey: .uname)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        levelInfo = try container.decodeIfPresent(CommentLevelInfo.self, forKey: .levelInfo)
    }
}

struct CommentLevelInfo: Decodable, Hashable {
    let currentLevel: Int?

    enum CodingKeys: String, CodingKey {
        case currentLevel = "current_level"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentLevel = container.decodeLossyIntIfPresent(forKey: .currentLevel)
    }
}

struct CommentContent: Decodable, Hashable {
    let message: String?
    let emotes: [String: CommentEmote]
    let pictures: [DynamicImageItem]
    let jumpURLs: DynamicJSONValue?
    private let hasGoodsMetadata: Bool

    enum CodingKeys: String, CodingKey {
        case message
        case emote
        case emotes
        case jumpURL = "jump_url"
        case jumpURLs = "jump_urls"
        case urls
        case pictures
        case pics
        case images
    }

    init(from decoder: Decoder) throws {
        let raw = try? DynamicJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = container.decodeLossyStringIfPresent(forKey: .message)
        let emoteMap = try container.decodeIfPresent([String: CommentEmote].self, forKey: .emote)
        let emotesMap = try container.decodeIfPresent([String: CommentEmote].self, forKey: .emotes)
        emotes = emoteMap ?? emotesMap ?? [:]
        jumpURLs = (try? container.decodeIfPresent(DynamicJSONValue.self, forKey: .jumpURL))
            ?? (try? container.decodeIfPresent(DynamicJSONValue.self, forKey: .jumpURLs))
            ?? (try? container.decodeIfPresent(DynamicJSONValue.self, forKey: .urls))
        pictures = (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pictures))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pics))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .images))
            ?? []
        hasGoodsMetadata = raw?.containsGoodsMetadata == true
    }

    func emote(for text: String) -> CommentEmote? {
        emotes[text] ?? emotes.values.first { $0.text == text }
    }

    var containsGoodsPromotion: Bool {
        hasGoodsMetadata
            || message.map(BiliContentFilter.isGoodsText) == true
            || jumpURLs?.containsGoodsMetadata == true
    }
}

struct CommentEmote: Decodable, Hashable {
    let text: String?
    let url: String?
    let gifURL: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case text, url, width, height
        case gifURL = "gif_url"
        case gifUrl = "gifUrl"
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.decodeLossyStringIfPresent(forKey: .text)
        url = container.decodeLossyStringIfPresent(forKey: .url)
        gifURL = container.decodeLossyStringIfPresent(forKey: .gifURL)
            ?? container.decodeLossyStringIfPresent(forKey: .gifUrl)
        width = container.decodeLossyIntIfPresent(forKey: .width)
        height = container.decodeLossyIntIfPresent(forKey: .height)
    }

    var displayURL: String? {
        (url ?? gifURL)?.normalizedBiliURL()
    }
}

struct AccountVideoEntry: Identifiable, Hashable {
    var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let duration: Int?
    let owner: VideoOwner?
    let stat: VideoStat?
    let cid: Int?
    let savedAt: Date
    let playbackTime: TimeInterval?
    let playbackDuration: TimeInterval?

    var videoItem: VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic,
            desc: nil,
            duration: duration,
            pubdate: nil,
            owner: owner,
            stat: stat,
            cid: cid,
            pages: nil,
            dimension: nil
        )
    }

    var resumeTime: TimeInterval? {
        guard let playbackTime, playbackTime >= 10 else { return nil }
        if let playbackDuration, playbackDuration > 0 {
            let remaining = playbackDuration - playbackTime
            guard remaining > 15, playbackTime / playbackDuration < 0.96 else { return nil }
        }
        return playbackTime
    }

    var playbackProgress: Double? {
        guard let playbackTime, playbackTime > 0 else { return nil }
        guard let playbackDuration, playbackDuration > 0 else { return nil }
        return min(max(playbackTime / playbackDuration, 0), 1)
    }
}

struct SearchTypeData<Result: Decodable>: Decodable {
    let result: [Result]?
}

struct SearchVideoItem: Identifiable, Decodable, Hashable {
    var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let author: String?
    let mid: Int?
    let play: Int?
    let duration: String?
    let description: String?
    let pubdate: Int?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, title, pic, author, mid, play, duration, description, pubdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid) ?? ""
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        play = container.decodeLossyIntIfPresent(forKey: .play)
        duration = container.decodeLossyStringIfPresent(forKey: .duration)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
    }

    func asVideoItem() -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title.removingHTMLTags(),
            pic: pic?.normalizedBiliURL(),
            desc: description,
            duration: duration.flatMap(Self.durationSeconds),
            pubdate: pubdate,
            owner: VideoOwner(mid: mid ?? 0, name: author ?? "", face: nil),
            stat: VideoStat(view: play, reply: nil, like: nil, coin: nil, favorite: nil),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated private static func durationSeconds(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return 0
    }
}

struct SearchUserItem: Identifiable, Decodable, Hashable {
    var id: Int { mid }

    let mid: Int
    let name: String
    let face: String?
    let sign: String?
    let fans: Int?
    let videos: Int?
    let officialDescription: String?
    let isFollowing: Bool?

    enum CodingKeys: String, CodingKey {
        case mid, fans, videos
        case name = "uname"
        case face = "upic"
        case sign = "usign"
        case officialVerify = "official_verify"
        case isFollowing = "is_atten"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid) ?? 0
        name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Unknown").removingHTMLTags()
        face = try? container.decodeIfPresent(String.self, forKey: .face)
        sign = try? container.decodeIfPresent(String.self, forKey: .sign)
        fans = container.decodeLossyIntIfPresent(forKey: .fans)
        videos = container.decodeLossyIntIfPresent(forKey: .videos)
        officialDescription = try? container.decodeIfPresent(SearchUserOfficialVerify.self, forKey: .officialVerify)?.desc
        isFollowing = container.decodeLossyBoolIfPresent(forKey: .isFollowing)
    }

    var owner: VideoOwner {
        VideoOwner(mid: mid, name: name, face: face?.normalizedBiliURL())
    }
}

struct SearchUserOfficialVerify: Decodable, Hashable {
    let desc: String?
}

struct SearchMediaItem: Identifiable, Decodable, Hashable {
    var id: String {
        if let mediaID {
            return "media-\(mediaID)"
        }
        if let seasonID {
            return "season-\(seasonID)"
        }
        return title
    }

    let mediaID: Int?
    let seasonID: Int?
    let title: String
    let cover: String?
    let description: String?
    let typeName: String?
    let indexShow: String?
    let rating: String?
    let stylesText: String?
    let url: String?
    let gotoURL: String?

    enum CodingKeys: String, CodingKey {
        case title, cover, url, rating, styles
        case mediaID = "media_id"
        case seasonID = "season_id"
        case description = "desc"
        case typeName = "season_type_name"
        case indexShow = "index_show"
        case gotoURL = "goto_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = container.decodeLossyIntIfPresent(forKey: .mediaID)
        seasonID = container.decodeLossyIntIfPresent(forKey: .seasonID)
        title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Untitled").removingHTMLTags()
        cover = try? container.decodeIfPresent(String.self, forKey: .cover)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        typeName = try? container.decodeIfPresent(String.self, forKey: .typeName)
        indexShow = try? container.decodeIfPresent(String.self, forKey: .indexShow)
        rating = (try? container.decodeIfPresent(SearchMediaRating.self, forKey: .rating))?.displayScore
            ?? container.decodeLossyStringIfPresent(forKey: .rating)
        stylesText = (try? container.decodeIfPresent([String].self, forKey: .styles))?.joined(separator: " / ")
            ?? container.decodeLossyStringIfPresent(forKey: .styles)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        gotoURL = try? container.decodeIfPresent(String.self, forKey: .gotoURL)
    }

    var destinationURL: URL? {
        for rawURL in [url, gotoURL] {
            guard let rawURL, !rawURL.isEmpty else { continue }
            let normalized = rawURL.normalizedBiliURL()
            if let url = URL(string: normalized) {
                return url
            }
        }
        if let seasonID {
            return URL(string: "https://www.bilibili.com/bangumi/play/ss\(seasonID)")
        }
        if let mediaID {
            return URL(string: "https://www.bilibili.com/bangumi/media/md\(mediaID)")
        }
        return nil
    }
}

struct SearchMediaRating: Decodable, Hashable {
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = (try? container.decodeIfPresent(Double.self, forKey: .score))
            ?? container.decodeLossyStringIfPresent(forKey: .score).flatMap(Double.init)
    }

    var displayScore: String? {
        guard let score else { return nil }
        return String(format: "%.1f", score)
    }
}

struct SearchArticleItem: Identifiable, Decodable, Hashable {
    var id: Int { articleID }

    let articleID: Int
    let title: String
    let description: String?
    let author: String?
    let imageURLs: [String]
    let view: Int?
    let reply: Int?
    let like: Int?
    let pubTime: Int?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case title, author, view, reply, like, url
        case articleID = "id"
        case description = "desc"
        case imageURLs = "image_urls"
        case pubTime = "pub_time"
        case pubTimeAlt = "pubdate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleID = container.decodeLossyIntIfPresent(forKey: .articleID) ?? 0
        title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Untitled").removingHTMLTags()
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        author = try? container.decodeIfPresent(String.self, forKey: .author)
        imageURLs = ((try? container.decodeIfPresent([String].self, forKey: .imageURLs)) ?? [])
            .map { $0.normalizedBiliURL() }
        view = container.decodeLossyIntIfPresent(forKey: .view)
        reply = container.decodeLossyIntIfPresent(forKey: .reply)
        like = container.decodeLossyIntIfPresent(forKey: .like)
        pubTime = container.decodeLossyIntIfPresent(forKey: .pubTime)
            ?? container.decodeLossyIntIfPresent(forKey: .pubTimeAlt)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
    }

    var destinationURL: URL? {
        if let url, !url.isEmpty, let destination = URL(string: url.normalizedBiliURL()) {
            return destination
        }
        guard articleID > 0 else { return nil }
        return URL(string: "https://www.bilibili.com/read/cv\(articleID)")
    }
}

struct SearchSuggestResponse: Decodable {
    let tag: [SearchSuggestItem]?
}

struct SearchSuggestItem: Identifiable, Decodable, Hashable {
    var id: String { value }

    let value: String
    let ref: Int?
}

struct HotSearchData: Decodable {
    let trending: HotSearchTrending?
}

struct HotSearchTrending: Decodable {
    let list: [HotSearchItem]?
}

struct HotSearchItem: Identifiable, Decodable, Hashable {
    var id: String { keyword }

    let keyword: String
    let showName: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case keyword, icon
        case showName = "show_name"
    }
}

struct EmptyBiliPayload: Decodable {}

struct VideoInteractionState: Hashable {
    var isLiked = false
    var coinCount = 0
    var isFavorited = false
    var isFollowing = false

    var isCoined: Bool {
        coinCount > 0
    }
}

nonisolated struct VideoCoinState: Decodable, Hashable {
    let multiply: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        multiply = container.decodeLossyIntIfPresent(forKey: .multiply)
    }

    private enum CodingKeys: String, CodingKey {
        case multiply
    }
}

nonisolated struct VideoFavoriteState: Decodable, Hashable {
    let favoured: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoured = container.decodeLossyBoolIfPresent(forKey: .favoured)
    }

    private enum CodingKeys: String, CodingKey {
        case favoured
    }
}

struct FavoriteFolderListData: Decodable, Hashable {
    let list: [FavoriteFolder]?
}

struct FavoriteFolder: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String?
    let favState: Int?

    enum CodingKeys: String, CodingKey {
        case id, title
        case mediaID = "media_id"
        case favState = "fav_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id)
            ?? container.decodeLossyIntIfPresent(forKey: .mediaID)
            ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        favState = container.decodeLossyIntIfPresent(forKey: .favState)
    }
}

private func firstNonBlankDynamicText(_ values: [String?]) -> String? {
    values
        .compactMap { $0?.removingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
}

private func joinedDynamicText(_ values: [String?], separator: String = "") -> String? {
    let text = values
        .compactMap { $0?.removingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: separator)
    return text.isEmpty ? nil : text
}

enum DynamicTextSegment: Hashable {
    case text(String)
    case emoji(text: String, url: String?)
    case link(title: String, url: String)

    var displayText: String {
        switch self {
        case .text(let text):
            return text
        case .emoji(let text, _):
            return text
        case .link:
            return "查看链接"
        }
    }

    static func displayText(from segments: [DynamicTextSegment]) -> String? {
        firstNonBlankDynamicText([segments.map(\.displayText).joined()])
    }
}

private func firstNonEmptyDynamicSegments(_ values: [[DynamicTextSegment]]) -> [DynamicTextSegment] {
    values.first { segments in
        DynamicTextSegment.displayText(from: segments)?.isEmpty == false
    } ?? []
}

private func normalizedDynamicSegments(_ segments: [DynamicTextSegment]) -> [DynamicTextSegment] {
    var result = [DynamicTextSegment]()
    for segment in segments {
        switch segment {
        case .text(let value):
            guard !value.isEmpty else { continue }
            if case .text(let previous) = result.last {
                result.removeLast()
                result.append(.text(previous + value))
            } else {
                result.append(.text(value))
            }
        case .emoji(let text, let url):
            guard !text.isEmpty else { continue }
            result.append(.emoji(text: text, url: url))
        case .link(let title, let url):
            guard !url.isEmpty else { continue }
            result.append(.link(title: title.isEmpty ? "查看链接" : title, url: url))
        }
    }
    return result
}

private func dynamicPlainTextSegments(_ text: String?) -> [DynamicTextSegment] {
    guard let text, !text.isEmpty else { return [] }

    let pattern = #"(?i)(?:https?:)?//[^\s<>"']+"#
    var result = [DynamicTextSegment]()
    var cursor = text.startIndex

    while cursor < text.endIndex,
          let range = text.range(of: pattern, options: .regularExpression, range: cursor..<text.endIndex) {
        if range.lowerBound > cursor {
            result.append(.text(String(text[cursor..<range.lowerBound])))
        }

        let rawURL = String(text[range])
        let trimmed = dynamicURLByTrimmingTrailingPunctuation(rawURL)
        if let url = normalizedOpenDynamicURL(trimmed.url) {
            result.append(.link(title: "查看链接", url: url))
        } else {
            result.append(.text(rawURL))
        }

        if !trimmed.trailing.isEmpty {
            result.append(.text(trimmed.trailing))
        }

        cursor = range.upperBound
    }

    if cursor < text.endIndex {
        result.append(.text(String(text[cursor...])))
    }

    return normalizedDynamicSegments(result)
}

private func normalizedOpenDynamicURL(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .normalizedBiliURL()
    guard let components = URLComponents(string: normalized),
          let scheme = components.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          components.host?.isEmpty == false
    else {
        return nil
    }
    return normalized
}

private func dynamicURLByTrimmingTrailingPunctuation(_ raw: String) -> (url: String, trailing: String) {
    let punctuation = CharacterSet(charactersIn: ".,，。!！?？;；:：、)]}）】》\"'")
    var url = raw
    var trailing = ""
    while let last = url.last,
          let scalar = String(last).unicodeScalars.first,
          punctuation.contains(scalar) {
        trailing.insert(last, at: trailing.startIndex)
        url.removeLast()
    }
    return (url, trailing)
}

private func shouldRenderDynamicLinkNode(type: String?, url: String?) -> Bool {
    let uppercasedType = (type ?? "").uppercased()
    if uppercasedType.contains("AT")
        || uppercasedType.contains("TOPIC")
        || uppercasedType.contains("EMOJI") {
        return false
    }
    if uppercasedType.contains("WEB")
        || uppercasedType.contains("LINK")
        || uppercasedType.contains("URL")
        || uppercasedType.contains("ARTICLE")
        || uppercasedType.contains("GOODS")
        || uppercasedType.contains("VOTE")
        || uppercasedType.contains("LOTTERY") {
        return true
    }
    return normalizedOpenDynamicURL(url) != nil
}

private func uniqueDynamicImages(_ groups: [[DynamicImageItem]]) -> [DynamicImageItem] {
    var seen = Set<String>()
    var result = [DynamicImageItem]()
    for item in groups.flatMap({ $0 }) {
        let key = item.normalizedURL ?? item.url
        guard !key.isEmpty, seen.insert(key).inserted else { continue }
        result.append(item)
    }
    return result
}

enum BiliContentFilter {
    nonisolated static let goodsURLPrefix = "https://gaoneng.bilibili.com/tetris"

    nonisolated static func isGoodsDynamicAdditionalType(_ type: String?) -> Bool {
        guard let type else { return false }
        return type.uppercased().contains("ADDITIONAL_TYPE_GOODS")
    }

    nonisolated static func isGoodsKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("goods")
            || normalized.contains("commodity")
            || normalized.contains("commerce")
            || normalized.contains("shopping")
            || normalized.contains("shop")
            || normalized.contains("mall")
    }

    nonisolated static func isGoodsText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains(goodsURLPrefix)
            || normalized.contains("additional_type_goods")
            || normalized.contains("desc_type_goods")
            || normalized.contains("goods_cm_control")
            || normalized.contains("goods_item_id")
            || normalized.contains("goods_prefetched_cache")
            || normalized.contains("gaoneng.bilibili.com/tetris")
            || normalized.contains("mall.bilibili.com")
            || normalized.contains("b23.tv/mall")
            || normalized.contains("bilibili.com/mall")
            || normalized.contains("会员购")
            || normalized.contains("小黄车")
            || normalized.contains("small_shop")
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum DynamicJSONValue: Decodable, Hashable {
    case string(String)
    case number(String)
    case bool(Bool)
    case array([DynamicJSONValue])
    case object([String: DynamicJSONValue])
    case null

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values = [DynamicJSONValue]()
            while !array.isAtEnd {
                if let value = try? array.decode(DynamicJSONValue.self) {
                    values.append(value)
                } else {
                    _ = try? array.decode(DynamicDiscardedValue.self)
                }
            }
            self = .array(values)
            return
        }

        if let object = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var values = [String: DynamicJSONValue]()
            for key in object.allKeys {
                values[key.stringValue] = try? object.decode(DynamicJSONValue.self, forKey: key)
            }
            self = .object(values)
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode(Int.self) {
            self = .number(String(value))
        } else if let value = try? single.decode(Double.self) {
            self = .number(String(format: "%.3f", value))
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    var textValue: String? {
        switch self {
        case .string(let value), .number(let value):
            return value
        case .bool, .array, .object, .null:
            return nil
        }
    }

    var dynamicDisplayText: String? {
        switch self {
        case .string(let value), .number(let value):
            return value
        case .array(let values):
            return joinedDynamicText(values.map(\.dynamicDisplayText))
        case .object(let object):
            if let richText = object["rich_text_nodes"]?.richTextNodesDisplayText {
                return richText
            }
            return firstNonBlankDynamicText([
                object["text"]?.dynamicDisplayText,
                object["orig_text"]?.dynamicDisplayText,
                object["raw_text"]?.dynamicDisplayText,
                object["content"]?.dynamicDisplayText,
                object["summary"]?.dynamicDisplayText,
                object["desc"]?.dynamicDisplayText,
                object["title"]?.dynamicDisplayText
            ])
        case .bool, .null:
            return nil
        }
    }

    var dynamicTextSegments: [DynamicTextSegment] {
        switch self {
        case .string(let value), .number(let value):
            return dynamicPlainTextSegments(value)
        case .array(let values):
            return normalizedDynamicSegments(values.flatMap(\.dynamicTextSegments))
        case .object(let object):
            if let richText = object["rich_text_nodes"]?.richTextNodesSegments, !richText.isEmpty {
                return richText
            }
            return firstNonEmptyDynamicSegments([
                object["text"]?.dynamicTextSegments ?? [],
                object["orig_text"]?.dynamicTextSegments ?? [],
                object["raw_text"]?.dynamicTextSegments ?? [],
                object["content"]?.dynamicTextSegments ?? [],
                object["summary"]?.dynamicTextSegments ?? [],
                object["desc"]?.dynamicTextSegments ?? [],
                object["title"]?.dynamicTextSegments ?? []
            ])
        case .bool, .null:
            return []
        }
    }

    var richTextNodesDisplayText: String? {
        DynamicTextSegment.displayText(from: richTextNodesSegments)
    }

    var richTextNodesSegments: [DynamicTextSegment] {
        switch self {
        case .array(let values):
            return normalizedDynamicSegments(values.flatMap(\.richTextNodeSegments))
        case .object:
            return richTextNodeSegments
        case .string(let value), .number(let value):
            return dynamicPlainTextSegments(value)
        case .bool, .null:
            return []
        }
    }

    var richTextNodeDisplayText: String? {
        DynamicTextSegment.displayText(from: richTextNodeSegments)
    }

    var richTextNodeSegments: [DynamicTextSegment] {
        switch self {
        case .object(let object):
            let type = object["type"]?.textValue
            let emojiObject = object["emoji"]?.objectValue
            let text = firstNonBlankDynamicText([
                object["text"]?.textValue,
                object["orig_text"]?.textValue,
                object["raw_text"]?.textValue,
                emojiObject?["text"]?.textValue
            ])
            let emojiText = firstNonBlankDynamicText([
                emojiObject?["text"]?.textValue,
                object["emoji"]?.textValue,
                text
            ])
            let emojiURL = firstNonBlankDynamicText([
                emojiObject?["icon_url"]?.textValue,
                emojiObject?["url"]?.textValue,
                emojiObject?["gif_url"]?.textValue,
                emojiObject?["image_url"]?.textValue,
                emojiObject?["img_url"]?.textValue,
                emojiObject?["webp_url"]?.textValue,
                object["icon_url"]?.textValue,
                object["emoji_url"]?.textValue
            ])?.normalizedBiliURL()

            if emojiObject != nil || (type ?? "").uppercased().contains("EMOJI") {
                if let emojiText, !emojiText.isEmpty {
                    return [.emoji(text: emojiText, url: emojiURL)]
                }
            }

            let linkCandidate = firstNonBlankDynamicText([
                object["jump_url"]?.textValue,
                object["url"]?.textValue,
                object["uri"]?.textValue,
                object["link"]?.textValue
            ])
            if shouldRenderDynamicLinkNode(type: type, url: linkCandidate),
               let url = normalizedOpenDynamicURL(linkCandidate ?? text) {
                return [.link(title: "查看链接", url: url)]
            }

            return dynamicPlainTextSegments(text)
        case .string(let value), .number(let value):
            return dynamicPlainTextSegments(value)
        case .array, .bool, .null:
            return []
        }
    }

    var dynamicImageItems: [DynamicImageItem] {
        switch self {
        case .array(let values):
            return values.flatMap(\.dynamicImageItems)
        case .object(let object):
            var groups = [[DynamicImageItem]]()
            if let image = imageItem(from: object) {
                groups.append([image])
            }
            for key in ["pics", "images", "items", "covers"] {
                groups.append(object[key]?.dynamicImageItems ?? [])
            }
            return uniqueDynamicImages(groups)
        case .string, .number, .bool, .null:
            return []
        }
    }

    var dynamicMajorFallbackDisplayText: String? {
        switch self {
        case .object(let object):
            return firstNonBlankDynamicText([
                object["common"]?.dynamicDisplayText,
                object["article"]?.dynamicDisplayText,
                object["pgc"]?.dynamicDisplayText,
                object["courses"]?.dynamicDisplayText,
                object["music"]?.dynamicDisplayText,
                object["medialist"]?.dynamicDisplayText,
                object["ugc_season"]?.dynamicDisplayText
            ])
        case .array(let values):
            return firstNonBlankDynamicText(values.map(\.dynamicMajorFallbackDisplayText))
        case .string, .number, .bool, .null:
            return nil
        }
    }

    var dynamicMajorFallbackTextSegments: [DynamicTextSegment] {
        switch self {
        case .object(let object):
            return firstNonEmptyDynamicSegments([
                object["common"]?.dynamicTextSegments ?? [],
                object["article"]?.dynamicTextSegments ?? [],
                object["pgc"]?.dynamicTextSegments ?? [],
                object["courses"]?.dynamicTextSegments ?? [],
                object["music"]?.dynamicTextSegments ?? [],
                object["medialist"]?.dynamicTextSegments ?? [],
                object["ugc_season"]?.dynamicTextSegments ?? []
            ])
        case .array(let values):
            return firstNonEmptyDynamicSegments(values.map(\.dynamicMajorFallbackTextSegments))
        case .string, .number, .bool, .null:
            return []
        }
    }

    var dynamicMajorFallbackImageItems: [DynamicImageItem] {
        switch self {
        case .object(let object):
            return uniqueDynamicImages([
                object["common"]?.dynamicImageItems ?? [],
                object["article"]?.dynamicImageItems ?? [],
                object["pgc"]?.dynamicImageItems ?? [],
                object["courses"]?.dynamicImageItems ?? [],
                object["music"]?.dynamicImageItems ?? [],
                object["medialist"]?.dynamicImageItems ?? [],
                object["ugc_season"]?.dynamicImageItems ?? []
            ])
        case .array(let values):
            return uniqueDynamicImages(values.map(\.dynamicMajorFallbackImageItems))
        case .string, .number, .bool, .null:
            return []
        }
    }

    var containsGoodsMetadata: Bool {
        switch self {
        case .string(let value), .number(let value):
            return BiliContentFilter.isGoodsText(value)
        case .bool, .null:
            return false
        case .array(let values):
            return values.contains(where: \.containsGoodsMetadata)
        case .object(let object):
            for (key, value) in object {
                if BiliContentFilter.isGoodsKey(key), !value.isEmptyMetadataValue {
                    return true
                }
                if BiliContentFilter.isGoodsText(key) || value.containsGoodsMetadata {
                    return true
                }
            }
            return false
        }
    }

    var accountVideoEntries: [AccountVideoEntry] {
        switch self {
        case .array(let values):
            return values.compactMap(\.accountVideoEntry)
        case .object(let object):
            for key in ["list", "medias", "items", "archives"] {
                let entries = object[key]?.accountVideoEntries ?? []
                if !entries.isEmpty {
                    return entries
                }
            }
            if let entry = accountVideoEntry {
                return [entry]
            }
            return []
        case .string, .number, .bool, .null:
            return []
        }
    }

    var intValueForDynamicParsing: Int? {
        intValue
    }

    var textValueForDynamicParsing: String? {
        textValue
    }

    var objectValueForDynamicParsing: [String: DynamicJSONValue]? {
        objectValue
    }

    private var accountVideoEntry: AccountVideoEntry? {
        guard case .object(let object) = self else { return nil }
        let history = object["history"]?.objectValue
        let upper = object["upper"]?.objectValue
        let ownerObject = object["owner"]?.objectValue
        let statObject = object["stat"]?.objectValue ?? object["cnt_info"]?.objectValue
        let bvid = firstNonBlankDynamicText([
            object["bvid"]?.textValue,
            history?["bvid"]?.textValue,
            object["bvid_str"]?.textValue
        ]) ?? Self.bvid(from: firstNonBlankDynamicText([
            object["uri"]?.textValue,
            object["url"]?.textValue,
            object["link"]?.textValue
        ]))
        guard let bvid, !bvid.isEmpty else { return nil }

        let aid = object["aid"]?.intValue
            ?? object["id"]?.intValue
            ?? object["rid"]?.intValue
            ?? history?["oid"]?.intValue
            ?? history?["aid"]?.intValue
        let title = firstNonBlankDynamicText([
            object["title"]?.textValue,
            object["long_title"]?.textValue,
            object["name"]?.textValue
        ]) ?? "未命名视频"
        let pic = firstNonBlankDynamicText([
            object["pic"]?.textValue,
            object["cover"]?.textValue,
            object["cover_url"]?.textValue,
            object["thumbnail"]?.textValue
        ])?.normalizedBiliURL()
        let duration = object["duration"]?.intValue
        let cid = object["cid"]?.intValue ?? history?["cid"]?.intValue
        let ownerMID = upper?["mid"]?.intValue
            ?? ownerObject?["mid"]?.intValue
            ?? object["author_mid"]?.intValue
            ?? object["mid"]?.intValue
        let ownerName = firstNonBlankDynamicText([
            upper?["name"]?.textValue,
            ownerObject?["name"]?.textValue,
            object["author_name"]?.textValue,
            object["author"]?.textValue,
            object["owner_name"]?.textValue
        ])
        let ownerFace = firstNonBlankDynamicText([
            upper?["face"]?.textValue,
            ownerObject?["face"]?.textValue,
            object["author_face"]?.textValue,
            object["owner_face"]?.textValue
        ])?.normalizedBiliURL()
        let owner = (ownerMID != nil || ownerName != nil || ownerFace != nil)
            ? VideoOwner(mid: ownerMID ?? 0, name: ownerName ?? "", face: ownerFace)
            : nil
        let stat = VideoStat(
            view: statObject?["play"]?.intValue ?? statObject?["view"]?.intValue,
            reply: statObject?["reply"]?.intValue,
            like: statObject?["like"]?.intValue,
            coin: statObject?["coin"]?.intValue,
            favorite: statObject?["collect"]?.intValue ?? statObject?["favorite"]?.intValue
        )
        let timestamp = object["view_at"]?.doubleValue
            ?? object["fav_time"]?.doubleValue
            ?? object["mtime"]?.doubleValue
            ?? object["ctime"]?.doubleValue
        let progress = object["progress"]?.doubleValue
        let playbackTime = progress.map { $0 < 0 ? TimeInterval(duration ?? 0) : TimeInterval($0) }

        return AccountVideoEntry(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic,
            duration: duration,
            owner: owner,
            stat: stat,
            cid: cid,
            savedAt: timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date(),
            playbackTime: playbackTime,
            playbackDuration: duration.map(TimeInterval.init)
        )
    }

    private func imageItem(from object: [String: DynamicJSONValue]) -> DynamicImageItem? {
        let url = firstNonBlankDynamicText([
            object["src"]?.textValue,
            object["url"]?.textValue,
            object["img_src"]?.textValue,
            object["raw_url"]?.textValue,
            object["image_url"]?.textValue,
            object["cover"]?.textValue,
            object["cover_url"]?.textValue,
            object["pic"]?.textValue,
            object["thumb"]?.textValue,
            object["thumbnail"]?.textValue
        ])
        guard let url, !url.isEmpty else { return nil }
        return DynamicImageItem(
            url: url,
            width: object["width"]?.intValue,
            height: object["height"]?.intValue,
            size: object["size"]?.doubleValue
        )
    }

    private var intValue: Int? {
        switch self {
        case .number(let value), .string(let value):
            return Int(value)
        case .bool(let value):
            return value ? 1 : 0
        case .array, .object, .null:
            return nil
        }
    }

    private var doubleValue: Double? {
        switch self {
        case .number(let value), .string(let value):
            return Double(value)
        case .bool, .array, .object, .null:
            return nil
        }
    }

    private var objectValue: [String: DynamicJSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    private var isEmptyMetadataValue: Bool {
        switch self {
        case .null:
            return true
        case .string(let value), .number(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .bool:
            return false
        case .array(let values):
            return values.isEmpty
        case .object(let object):
            return object.isEmpty
        }
    }

    private static func bvid(from text: String?) -> String? {
        guard let text else { return nil }
        guard let range = text.range(of: #"BV[A-Za-z0-9]{10,}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

private struct DynamicDiscardedValue: Decodable {}

struct DynamicFeedData: Decodable, Hashable {
    let items: [DynamicFeedItem]?
    let hasMore: Bool?
    let offset: String?

    enum CodingKeys: String, CodingKey {
        case items, offset
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([DynamicFeedItem].self, forKey: .items)
        hasMore = container.decodeLossyBoolIfPresent(forKey: .hasMore)
        offset = container.decodeLossyStringIfPresent(forKey: .offset)
    }
}

struct DynamicFeedItem: Identifiable, Decodable, Hashable {
    var id: String { idStr }

    let idStr: String
    let type: String?
    let basic: DynamicBasic?
    let modules: DynamicModules?
    let original: DynamicOriginalItem?

    var author: DynamicAuthor? {
        modules?.moduleAuthor
    }

    var displayText: String? {
        firstNonBlankDynamicText([
            modules?.moduleDynamic?.desc?.displayText,
            modules?.moduleDynamic?.major?.displayText
        ])
    }

    var textSegments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            modules?.moduleDynamic?.desc?.segments ?? [],
            modules?.moduleDynamic?.major?.segments ?? []
        ])
    }

    var archive: DynamicArchive? {
        modules?.moduleDynamic?.major?.archive
    }

    var live: DynamicLive? {
        modules?.moduleDynamic?.major?.live
    }

    var imageItems: [DynamicImageItem] {
        uniqueDynamicImages([
            modules?.moduleDynamic?.major?.imageItems ?? [],
            modules?.moduleDynamic?.desc?.imageItems ?? []
        ])
    }

    var isForward: Bool {
        type == "DYNAMIC_TYPE_FORWARD"
    }

    var containsGoodsPromotion: Bool {
        modules?.moduleDynamic?.containsGoodsPromotion == true
            || original?.containsGoodsPromotion == true
    }

    var replyCount: Int? {
        modules?.moduleStat?.comment?.count
            ?? modules?.moduleStat?.reply?.count
            ?? modules?.moduleStat?.comments?.count
    }

    var repostCount: Int? {
        modules?.moduleStat?.forward?.count
            ?? modules?.moduleStat?.repost?.count
    }

    var likeCount: Int? {
        modules?.moduleStat?.like?.count
    }

    var isLiked: Bool {
        modules?.moduleStat?.like?.status == true
    }

    var commentOID: String? {
        firstNonBlankDynamicText([
            basic?.commentIDStr,
            basic?.ridStr,
            idStr
        ])
    }

    var commentType: Int? {
        basic?.commentType
    }

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case idValue = "id"
        case type, basic, modules
        case original = "orig"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idStr = container.decodeLossyStringIfPresent(forKey: .idStr)
            ?? container.decodeLossyStringIfPresent(forKey: .idValue)
            ?? UUID().uuidString
        type = try container.decodeIfPresent(String.self, forKey: .type)
        basic = try? container.decodeIfPresent(DynamicBasic.self, forKey: .basic)
        modules = try container.decodeIfPresent(DynamicModules.self, forKey: .modules)
        original = try? container.decodeIfPresent(DynamicOriginalItem.self, forKey: .original)
    }
}

struct DynamicBasic: Decodable, Hashable {
    let commentIDStr: String?
    let commentType: Int?
    let ridStr: String?

    enum CodingKeys: String, CodingKey {
        case commentIDStr = "comment_id_str"
        case commentType = "comment_type"
        case ridStr = "rid_str"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commentIDStr = container.decodeLossyStringIfPresent(forKey: .commentIDStr)
        commentType = container.decodeLossyIntIfPresent(forKey: .commentType)
        ridStr = container.decodeLossyStringIfPresent(forKey: .ridStr)
    }
}

struct DynamicOriginalItem: Identifiable, Decodable, Hashable {
    var id: String { idStr }

    let idStr: String
    let type: String?
    let modules: DynamicModules?
    let visible: Bool?

    var author: DynamicAuthor? {
        modules?.moduleAuthor
    }

    var displayText: String? {
        firstNonBlankDynamicText([
            modules?.moduleDynamic?.desc?.displayText,
            modules?.moduleDynamic?.major?.displayText
        ])
    }

    var textSegments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            modules?.moduleDynamic?.desc?.segments ?? [],
            modules?.moduleDynamic?.major?.segments ?? []
        ])
    }

    var archive: DynamicArchive? {
        modules?.moduleDynamic?.major?.archive
    }

    var live: DynamicLive? {
        modules?.moduleDynamic?.major?.live
    }

    var imageItems: [DynamicImageItem] {
        uniqueDynamicImages([
            modules?.moduleDynamic?.major?.imageItems ?? [],
            modules?.moduleDynamic?.desc?.imageItems ?? []
        ])
    }

    var hasDisplayableContent: Bool {
        displayText?.isEmpty == false
            || DynamicTextSegment.displayText(from: textSegments)?.isEmpty == false
            || archive != nil
            || live != nil
            || !imageItems.isEmpty
    }

    var containsGoodsPromotion: Bool {
        modules?.moduleDynamic?.containsGoodsPromotion == true
    }

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case idValue = "id"
        case type, modules, visible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idStr = container.decodeLossyStringIfPresent(forKey: .idStr)
            ?? container.decodeLossyStringIfPresent(forKey: .idValue)
            ?? UUID().uuidString
        type = try container.decodeIfPresent(String.self, forKey: .type)
        modules = try container.decodeIfPresent(DynamicModules.self, forKey: .modules)
        visible = container.decodeLossyBoolIfPresent(forKey: .visible)
    }
}

struct DynamicModules: Decodable, Hashable {
    let moduleAuthor: DynamicAuthor?
    let moduleDynamic: DynamicModuleDynamic?
    let moduleStat: DynamicModuleStat?

    enum CodingKeys: String, CodingKey {
        case moduleAuthor = "module_author"
        case moduleDynamic = "module_dynamic"
        case moduleStat = "module_stat"
    }
}

struct DynamicAuthor: Decodable, Hashable {
    let mid: Int?
    let name: String?
    let face: String?
    let pubTime: String?
    let pubTS: Int?

    enum CodingKeys: String, CodingKey {
        case mid, name, face
        case pubTime = "pub_time"
        case pubTS = "pub_ts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        pubTime = try container.decodeIfPresent(String.self, forKey: .pubTime)
        pubTS = container.decodeLossyIntIfPresent(forKey: .pubTS)
    }

    var owner: VideoOwner {
        VideoOwner(mid: mid ?? 0, name: name ?? "", face: face)
    }
}

struct DynamicModuleDynamic: Decodable, Hashable {
    let desc: DynamicText?
    let major: DynamicMajor?
    let additional: DynamicAdditional?

    enum CodingKeys: String, CodingKey {
        case desc, major, additional
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desc = try? container.decodeIfPresent(DynamicText.self, forKey: .desc)
        major = try? container.decodeIfPresent(DynamicMajor.self, forKey: .major)
        additional = try? container.decodeIfPresent(DynamicAdditional.self, forKey: .additional)
    }

    var containsGoodsPromotion: Bool {
        additional?.containsGoodsPromotion == true
            || desc?.containsGoodsPromotion == true
            || major?.containsGoodsPromotion == true
    }
}

struct DynamicText: Decodable, Hashable {
    let text: String?
    let segments: [DynamicTextSegment]
    let imageItems: [DynamicImageItem]
    let containsGoodsPromotion: Bool

    var displayText: String? {
        firstNonBlankDynamicText([
            DynamicTextSegment.displayText(from: segments),
            text
        ])
    }

    enum CodingKeys: String, CodingKey {
        case text, content
        case rawText = "raw_text"
        case origText = "orig_text"
        case richTextNodes = "rich_text_nodes"
    }

    init(from decoder: Decoder) throws {
        let raw = try DynamicJSONValue(from: decoder)
        text = raw.dynamicDisplayText
        segments = raw.dynamicTextSegments
        imageItems = raw.dynamicImageItems
        containsGoodsPromotion = raw.containsGoodsMetadata
    }
}

struct DynamicAdditional: Decodable, Hashable {
    let type: String?
    let raw: DynamicJSONValue

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        raw = try DynamicJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.decodeLossyStringIfPresent(forKey: .type)
    }

    var containsGoodsPromotion: Bool {
        BiliContentFilter.isGoodsDynamicAdditionalType(type)
            || raw.containsGoodsMetadata
    }
}

struct DynamicRichTextNode: Decodable, Hashable {
    let text: String?
    let origText: String?
    let emoji: DynamicRichTextEmoji?

    enum CodingKeys: String, CodingKey {
        case text, emoji
        case origText = "orig_text"
    }

    var displayText: String {
        firstNonBlankDynamicText([text, origText, emoji?.text]) ?? ""
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.decodeLossyStringIfPresent(forKey: .text)
        origText = container.decodeLossyStringIfPresent(forKey: .origText)
        emoji = try? container.decodeIfPresent(DynamicRichTextEmoji.self, forKey: .emoji)
    }
}

struct DynamicRichTextEmoji: Decodable, Hashable {
    let text: String?

    enum CodingKeys: String, CodingKey {
        case text
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            text = value
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.decodeLossyStringIfPresent(forKey: .text)
    }
}

struct DynamicMajor: Decodable, Hashable {
    let archive: DynamicArchive?
    let opus: DynamicOpus?
    let draw: DynamicDraw?
    let live: DynamicLive?
    let fallbackDisplayText: String?
    let fallbackSegments: [DynamicTextSegment]
    let fallbackImageItems: [DynamicImageItem]

    var displayText: String? {
        firstNonBlankDynamicText([
            draw?.displayText,
            opus?.displayText,
            fallbackDisplayText
        ])
    }

    var segments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            draw?.segments ?? [],
            opus?.segments ?? [],
            fallbackSegments
        ])
    }

    var imageItems: [DynamicImageItem] {
        uniqueDynamicImages([
            draw?.items ?? [],
            opus?.pics ?? [],
            fallbackImageItems
        ])
    }

    var containsGoodsPromotion: Bool {
        draw?.containsGoodsPromotion == true
            || opus?.containsGoodsPromotion == true
    }

    enum CodingKeys: String, CodingKey {
        case archive, opus, draw, live
        case liveRcmd = "live_rcmd"
    }

    init(from decoder: Decoder) throws {
        let raw = try DynamicJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archive = try? container.decodeIfPresent(DynamicArchive.self, forKey: .archive)
        opus = try? container.decodeIfPresent(DynamicOpus.self, forKey: .opus)
        draw = try? container.decodeIfPresent(DynamicDraw.self, forKey: .draw)
        live = (try? container.decodeIfPresent(DynamicLive.self, forKey: .live))
            ?? (try? container.decodeIfPresent(DynamicLive.self, forKey: .liveRcmd))
        fallbackDisplayText = raw.dynamicMajorFallbackDisplayText
        fallbackSegments = raw.dynamicMajorFallbackTextSegments
        fallbackImageItems = raw.dynamicMajorFallbackImageItems
    }
}

struct DynamicLive: Decodable, Hashable {
    let title: String?
    let cover: String?
    let roomID: Int?
    let uid: Int?
    let link: String?
    let online: Int?
    let areaName: String?
    let watchedText: String?
    let liveStatus: Int?
    let badgeText: String?

    enum CodingKeys: String, CodingKey {
        case link, title, cover, uid, online
        case livePlayInfo = "live_play_info"
        case roomID = "room_id"
        case roomIDAlt = "roomid"
        case liveID = "live_id"
        case liveStatus = "live_status"
        case areaName = "area_name"
        case watchedShow = "watched_show"
        case coverURL = "cover_url"
        case keyframe
        case pendants
        case badgeText = "badge_text"
        case status
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self),
           let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(DynamicLive.self, from: data) {
            self = decoded
            return
        }

        let raw = try DynamicJSONValue(from: decoder)
        let object = raw.objectValueForDynamicParsing ?? [:]
        let playInfo = object["live_play_info"]?.objectValueForDynamicParsing
        let source = playInfo ?? object
        let watchedShow = source["watched_show"]?.objectValueForDynamicParsing
        let pendants = source["pendants"]?.objectValueForDynamicParsing ?? object["pendants"]?.objectValueForDynamicParsing

        title = firstNonBlankDynamicText([
            source["title"]?.textValueForDynamicParsing,
            object["title"]?.textValueForDynamicParsing,
            object["desc"]?.textValueForDynamicParsing
        ])
        cover = firstNonBlankDynamicText([
            source["cover"]?.textValueForDynamicParsing,
            source["cover_url"]?.textValueForDynamicParsing,
            source["keyframe"]?.textValueForDynamicParsing,
            object["cover"]?.textValueForDynamicParsing,
            object["cover_url"]?.textValueForDynamicParsing,
            object["pic"]?.textValueForDynamicParsing
        ])?.normalizedBiliURL()
        let linkValue = firstNonBlankDynamicText([
            source["link"]?.textValueForDynamicParsing,
            source["jump_url"]?.textValueForDynamicParsing,
            source["url"]?.textValueForDynamicParsing,
            object["link"]?.textValueForDynamicParsing,
            object["jump_url"]?.textValueForDynamicParsing
        ])?.normalizedBiliURL()
        roomID = source["room_id"]?.intValueForDynamicParsing
            ?? source["roomid"]?.intValueForDynamicParsing
            ?? Self.roomID(from: linkValue)
            ?? object["room_id"]?.intValueForDynamicParsing
            ?? object["roomid"]?.intValueForDynamicParsing
        uid = source["uid"]?.intValueForDynamicParsing ?? object["uid"]?.intValueForDynamicParsing
        link = linkValue
        online = source["online"]?.intValueForDynamicParsing
            ?? source["watched_show"]?.intValueForDynamicParsing
            ?? watchedShow?["num"]?.intValueForDynamicParsing
            ?? watchedShow?["watched_num"]?.intValueForDynamicParsing
        areaName = firstNonBlankDynamicText([
            source["area_name"]?.textValueForDynamicParsing,
            source["area"]?.textValueForDynamicParsing,
            object["area_name"]?.textValueForDynamicParsing
        ])
        watchedText = firstNonBlankDynamicText([
            watchedShow?["text_large"]?.textValueForDynamicParsing,
            watchedShow?["text_small"]?.textValueForDynamicParsing,
            watchedShow?["text"]?.textValueForDynamicParsing,
            watchedShow?["watched_show_text"]?.textValueForDynamicParsing,
            source["watched_show"]?.textValueForDynamicParsing
        ])
        liveStatus = source["live_status"]?.intValueForDynamicParsing
            ?? source["status"]?.intValueForDynamicParsing
            ?? object["live_status"]?.intValueForDynamicParsing
        badgeText = firstNonBlankDynamicText([
            source["badge_text"]?.textValueForDynamicParsing,
            object["badge_text"]?.textValueForDynamicParsing,
            Self.badgeText(from: pendants)
        ])
    }

    private static func roomID(from link: String?) -> Int? {
        guard let link, !link.isEmpty else { return nil }
        if let components = URLComponents(string: link) {
            for key in ["room_id", "roomid"] {
                if let value = components.queryItems?.first(where: { $0.name == key })?.value,
                   let roomID = Int(value) {
                    return roomID
                }
            }

            let pathParts = components.path.split(separator: "/").map(String.init)
            for part in pathParts.reversed() {
                if let roomID = Int(part) {
                    return roomID
                }
            }
        }

        if let range = link.range(of: #"live\.bilibili\.com/(?:h5/)?\d+"#, options: .regularExpression) {
            let matched = String(link[range])
            if let digitRange = matched.range(of: #"\d+"#, options: .regularExpression),
               let value = Int(matched[digitRange]) {
                return value
            }
        }
        return nil
    }

    private static func badgeText(from pendants: [String: DynamicJSONValue]?) -> String? {
        guard let pendants else { return nil }
        let candidates = pendants.values.compactMap(\.objectValueForDynamicParsing)
        for candidate in candidates {
            if let text = firstNonBlankDynamicText([
                candidate["text"]?.textValueForDynamicParsing,
                candidate["content"]?.textValueForDynamicParsing,
                candidate["name"]?.textValueForDynamicParsing
            ]) {
                return text
            }
        }
        return nil
    }

    var normalizedCoverURL: String? {
        cover?.normalizedBiliURL()
    }

    var normalizedLinkURL: URL? {
        guard let link, !link.isEmpty else { return nil }
        return URL(string: link.normalizedBiliURL())
    }

    var displayTitle: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : "直播中"
    }

    var statusText: String {
        if let badgeText, !badgeText.isEmpty {
            return badgeText
        }
        return liveStatus == 1 || liveStatus == nil ? "直播中" : "直播"
    }

    var viewerText: String? {
        if let watchedText, !watchedText.isEmpty {
            return watchedText
        }
        if let online, online > 0 {
            return "\(BiliFormatters.compactCount(online)) 人看过"
        }
        return nil
    }

    func asLiveRoom(author: DynamicAuthor?) -> LiveRoom? {
        let parsedRoomID = roomID ?? Self.roomID(from: link)
        let anchorUID = uid ?? author?.mid
        guard (parsedRoomID ?? 0) > 0 || (anchorUID ?? 0) > 0 else { return nil }
        return LiveRoom(
            roomID: parsedRoomID ?? 0,
            title: displayTitle,
            uname: author?.name ?? "Unknown",
            uid: anchorUID,
            face: author?.face,
            cover: cover,
            keyframe: cover,
            online: online,
            areaName: areaName,
            parentAreaName: nil,
            liveStatus: liveStatus
        )
    }
}

struct DynamicOpus: Decodable, Hashable {
    let title: String?
    let summary: DynamicText?
    let content: DynamicText?
    let desc: DynamicText?
    let pics: [DynamicImageItem]?

    enum CodingKeys: String, CodingKey {
        case title, summary, content, desc, pics, images, items
    }

    var displayText: String? {
        firstNonBlankDynamicText([
            summary?.displayText,
            content?.displayText,
            desc?.displayText,
            title
        ])
    }

    var segments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            summary?.segments ?? [],
            content?.segments ?? [],
            desc?.segments ?? [],
            dynamicPlainTextSegments(title)
        ])
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.decodeLossyStringIfPresent(forKey: .title)
        summary = try? container.decodeIfPresent(DynamicText.self, forKey: .summary)
        content = try? container.decodeIfPresent(DynamicText.self, forKey: .content)
        desc = try? container.decodeIfPresent(DynamicText.self, forKey: .desc)
        pics = (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pics))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .images))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .items))
    }

    var containsGoodsPromotion: Bool {
        summary?.containsGoodsPromotion == true
            || content?.containsGoodsPromotion == true
            || desc?.containsGoodsPromotion == true
    }
}

struct DynamicDraw: Decodable, Hashable {
    let items: [DynamicImageItem]?
    let title: String?
    let summary: DynamicText?
    let desc: DynamicText?

    var displayText: String? {
        firstNonBlankDynamicText([
            summary?.displayText,
            desc?.displayText,
            title
        ])
    }

    var segments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            summary?.segments ?? [],
            desc?.segments ?? [],
            dynamicPlainTextSegments(title)
        ])
    }

    enum CodingKeys: String, CodingKey {
        case items, title, summary, desc
        case pics, images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .items))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pics))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .images))
        title = container.decodeLossyStringIfPresent(forKey: .title)
        summary = try? container.decodeIfPresent(DynamicText.self, forKey: .summary)
        desc = try? container.decodeIfPresent(DynamicText.self, forKey: .desc)
    }

    var containsGoodsPromotion: Bool {
        summary?.containsGoodsPromotion == true
            || desc?.containsGoodsPromotion == true
    }
}

struct DynamicImageItem: Decodable, Hashable {
    let url: String
    let width: Int?
    let height: Int?
    let size: Double?

    enum CodingKeys: String, CodingKey {
        case src, url, width, height, size
        case imgSrc = "img_src"
        case imgWidth = "img_width"
        case imgHeight = "img_height"
        case imgSize = "img_size"
        case rawURL = "raw_url"
        case imageURL = "image_url"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
    }

    init(url: String, width: Int?, height: Int?, size: Double?) {
        self.url = url
        self.width = width
        self.height = height
        self.size = size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = container.decodeLossyStringIfPresent(forKey: .src)
            ?? container.decodeLossyStringIfPresent(forKey: .url)
            ?? container.decodeLossyStringIfPresent(forKey: .imgSrc)
            ?? container.decodeLossyStringIfPresent(forKey: .rawURL)
            ?? container.decodeLossyStringIfPresent(forKey: .imageURL)
            ?? ""
        width = container.decodeLossyIntIfPresent(forKey: .width)
            ?? container.decodeLossyIntIfPresent(forKey: .imgWidth)
            ?? container.decodeLossyIntIfPresent(forKey: .imageWidth)
        height = container.decodeLossyIntIfPresent(forKey: .height)
            ?? container.decodeLossyIntIfPresent(forKey: .imgHeight)
            ?? container.decodeLossyIntIfPresent(forKey: .imageHeight)
        size = (try? container.decodeIfPresent(Double.self, forKey: .size))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .imgSize))
            ?? container.decodeLossyStringIfPresent(forKey: .size).flatMap(Double.init)
            ?? container.decodeLossyStringIfPresent(forKey: .imgSize).flatMap(Double.init)
    }

    var normalizedURL: String? {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL()
        return normalized.isEmpty ? nil : normalized
    }

    var aspectRatio: Double {
        guard let width, let height, width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}

struct DynamicModuleStat: Decodable, Hashable {
    let like: DynamicStatItem?
    let reply: DynamicStatItem?
    let comment: DynamicStatItem?
    let comments: DynamicStatItem?
    let repost: DynamicStatItem?
    let forward: DynamicStatItem?

    enum CodingKeys: String, CodingKey {
        case like, reply, comment, comments, repost, forward
    }
}

struct DynamicStatItem: Decodable, Hashable {
    let count: Int?
    let status: Bool?

    enum CodingKeys: String, CodingKey {
        case count, status, text
        case countText = "count_text"
        case countStr = "count_str"
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if let value = try? single.decode(Int.self) {
                count = value
                status = nil
                return
            }
            if let value = try? single.decode(String.self),
               let parsed = Self.parseCount(value) {
                count = parsed
                status = nil
                return
            }
            if let value = try? single.decode(Bool.self) {
                count = nil
                status = value
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = container.decodeLossyIntIfPresent(forKey: .count)
            ?? Self.parseCount(container.decodeLossyStringIfPresent(forKey: .countText))
            ?? Self.parseCount(container.decodeLossyStringIfPresent(forKey: .countStr))
            ?? Self.parseCount(container.decodeLossyStringIfPresent(forKey: .text))
        status = container.decodeLossyBoolIfPresent(forKey: .status)
    }

    private static func parseCount(_ value: String?) -> Int? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        text = text.replacingOccurrences(of: ",", with: "")
        if let value = Int(text) {
            return value
        }

        let units: [(suffix: String, multiplier: Double)] = [
            ("亿", 100_000_000),
            ("万", 10_000)
        ]
        for unit in units where text.hasSuffix(unit.suffix) {
            let numberText = String(text.dropLast(unit.suffix.count))
            guard let number = Double(numberText) else { continue }
            return Int(number * unit.multiplier)
        }
        return nil
    }
}

struct DynamicArchive: Decodable, Hashable {
    let aid: Int?
    let bvid: String?
    let title: String?
    let cover: String?
    let desc: String?
    let durationText: String?
    let stat: DynamicArchiveStat?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, cover, desc, stat
        case durationText = "duration_text"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
        durationText = try container.decodeIfPresent(String.self, forKey: .durationText)
        stat = try container.decodeIfPresent(DynamicArchiveStat.self, forKey: .stat)
    }

    func asVideoItem(author: DynamicAuthor?) -> VideoItem? {
        guard let bvid, !bvid.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: aid,
            title: title ?? "视频",
            pic: cover?.normalizedBiliURL(),
            desc: desc,
            duration: durationText.flatMap(Self.durationSeconds),
            pubdate: author?.pubTS,
            owner: author?.owner,
            stat: VideoStat(
                view: stat?.play,
                reply: stat?.reply,
                like: stat?.like,
                coin: stat?.coin,
                favorite: stat?.favorite
            ),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated private static func durationSeconds(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return 0
    }
}

struct DynamicArchiveStat: Decodable, Hashable {
    let play: Int?
    let reply: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?

    enum CodingKeys: String, CodingKey {
        case play, reply, like, coin, favorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        play = container.decodeLossyIntIfPresent(forKey: .play)
        reply = container.decodeLossyIntIfPresent(forKey: .reply)
        like = container.decodeLossyIntIfPresent(forKey: .like)
        coin = container.decodeLossyIntIfPresent(forKey: .coin)
        favorite = container.decodeLossyIntIfPresent(forKey: .favorite)
    }
}

struct QRCodeLoginInfo: Decodable, Hashable {
    let url: String
    let qrcodeKey: String

    enum CodingKeys: String, CodingKey {
        case url
        case qrcodeKey = "qrcode_key"
    }
}

struct QRCodeLoginPollData: Decodable, Hashable {
    let url: String?
    let refreshToken: String?
    let timestamp: Int?
    let code: Int
    let message: String?

    enum CodingKeys: String, CodingKey {
        case url, timestamp, code, message
        case refreshToken = "refresh_token"
    }

    var status: QRCodeLoginPollStatus {
        switch code {
        case 0:
            return .confirmed
        case 86038:
            return .expired
        case 86090:
            return .waitingForConfirm
        case 86101:
            return .waitingForScan
        default:
            return .unknown(code)
        }
    }

    var cookieValuesFromURL: [String: String] {
        guard let url,
              let components = URLComponents(string: url),
              let queryItems = components.queryItems
        else {
            return [:]
        }

        return queryItems.reduce(into: [String: String]()) { result, item in
            guard let value = item.value, !value.isEmpty else { return }
            result[item.name] = value
        }
    }
}

struct QRCodeLoginPollResult {
    let data: QRCodeLoginPollData
    let cookies: [HTTPCookie]
}

enum QRCodeLoginPollStatus: Equatable {
    case waitingForScan
    case waitingForConfirm
    case confirmed
    case expired
    case unknown(Int)
}

struct LiveRecommendData: Decodable {
    let recommendRoomList: [LiveRoom]?

    enum CodingKeys: String, CodingKey {
        case recommendRoomList = "recommend_room_list"
    }
}

struct LiveAreaGroup: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let children: [LiveArea]

    enum CodingKeys: String, CodingKey {
        case id, name
        case children = "list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未知"
        children = try container.decodeIfPresent([LiveArea].self, forKey: .children) ?? []
    }
}

struct LiveArea: Identifiable, Decodable, Hashable {
    let id: Int
    let parentID: Int
    let name: String
    let parentName: String?
    let pic: String?

    enum CodingKeys: String, CodingKey {
        case id, name, pic
        case parentID = "parent_id"
        case parentName = "parent_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id) ?? 0
        parentID = container.decodeLossyIntIfPresent(forKey: .parentID) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未知"
        parentName = try container.decodeIfPresent(String.self, forKey: .parentName)
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
    }
}

struct LiveRoom: Identifiable, Decodable, Hashable {
    var id: Int { roomID }

    let roomID: Int
    let title: String
    let uname: String
    let uid: Int?
    let face: String?
    let cover: String?
    let keyframe: String?
    let online: Int?
    let areaName: String?
    let parentAreaName: String?
    let liveStatus: Int?

    init(
        roomID: Int,
        title: String,
        uname: String,
        uid: Int?,
        face: String?,
        cover: String?,
        keyframe: String?,
        online: Int?,
        areaName: String?,
        parentAreaName: String?,
        liveStatus: Int?
    ) {
        self.roomID = roomID
        self.title = title
        self.uname = uname
        self.uid = uid
        self.face = face
        self.cover = cover
        self.keyframe = keyframe
        self.online = online
        self.areaName = areaName
        self.parentAreaName = parentAreaName
        self.liveStatus = liveStatus
    }

    enum CodingKeys: String, CodingKey {
        case title, uname, uid, face, cover, keyframe, online
        case roomID = "roomid"
        case roomIDAlt = "room_id"
        case liveStatus = "live_status"
        case areaName = "area_v2_name"
        case parentAreaName = "area_v2_parent_name"
        case areaNameAlt = "area_name"
        case parentAreaNameAlt = "parent_area_name"
        case parentAreaNameV2 = "parent_area_v2_name"
        case userCover = "user_cover"
        case systemCover = "system_cover"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID = container.decodeLossyIntIfPresent(forKey: .roomID)
            ?? container.decodeLossyIntIfPresent(forKey: .roomIDAlt)
            ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        uname = try container.decodeIfPresent(String.self, forKey: .uname) ?? "Unknown"
        uid = container.decodeLossyIntIfPresent(forKey: .uid)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
            ?? container.decodeIfPresent(String.self, forKey: .userCover)
        keyframe = try container.decodeIfPresent(String.self, forKey: .keyframe)
            ?? container.decodeIfPresent(String.self, forKey: .systemCover)
        online = container.decodeLossyIntIfPresent(forKey: .online)
        liveStatus = container.decodeLossyIntIfPresent(forKey: .liveStatus)
        areaName = try container.decodeIfPresent(String.self, forKey: .areaName)
            ?? container.decodeIfPresent(String.self, forKey: .areaNameAlt)
        parentAreaName = try container.decodeIfPresent(String.self, forKey: .parentAreaName)
            ?? container.decodeIfPresent(String.self, forKey: .parentAreaNameV2)
            ?? container.decodeIfPresent(String.self, forKey: .parentAreaNameAlt)
    }

    var displayCover: String? {
        keyframe ?? cover
    }

    var isLive: Bool {
        liveStatus == nil || liveStatus == 1
    }
}

struct LiveRoomInfo: Decodable, Hashable {
    let roomID: Int
    let uid: Int?
    let title: String
    let userCover: String?
    let keyframe: String?
    let description: String?
    let liveStatus: Int?
    let online: Int?
    let areaName: String?
    let parentAreaName: String?
    let liveTime: String?

    enum CodingKeys: String, CodingKey {
        case uid, title, keyframe, description, online
        case roomID = "room_id"
        case userCover = "user_cover"
        case liveStatus = "live_status"
        case areaName = "area_name"
        case parentAreaName = "parent_area_name"
        case liveTime = "live_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID = container.decodeLossyIntIfPresent(forKey: .roomID) ?? 0
        uid = container.decodeLossyIntIfPresent(forKey: .uid)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        userCover = try container.decodeIfPresent(String.self, forKey: .userCover)
        keyframe = try container.decodeIfPresent(String.self, forKey: .keyframe)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        liveStatus = container.decodeLossyIntIfPresent(forKey: .liveStatus)
        online = container.decodeLossyIntIfPresent(forKey: .online)
        areaName = try container.decodeIfPresent(String.self, forKey: .areaName)
        parentAreaName = try container.decodeIfPresent(String.self, forKey: .parentAreaName)
        liveTime = try container.decodeIfPresent(String.self, forKey: .liveTime)
    }

    var displayCover: String? {
        keyframe ?? userCover
    }

    var isLive: Bool {
        liveStatus == 1
    }
}

struct LiveRoomSummary: Decodable, Hashable {
    let roomID: Int
    let liveStatus: Int?
    let title: String?
    let cover: String?
    let online: Int?
    let link: String?

    enum CodingKeys: String, CodingKey {
        case title, cover, online, link
        case roomID = "roomid"
        case roomIDAlt = "room_id"
        case liveStatus = "liveStatus"
        case liveStatusAlt = "live_status"
        case roomStatus = "roomStatus"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID = container.decodeLossyIntIfPresent(forKey: .roomID)
            ?? container.decodeLossyIntIfPresent(forKey: .roomIDAlt)
            ?? 0
        liveStatus = container.decodeLossyIntIfPresent(forKey: .liveStatus)
            ?? container.decodeLossyIntIfPresent(forKey: .liveStatusAlt)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        online = container.decodeLossyIntIfPresent(forKey: .online)
        link = try container.decodeIfPresent(String.self, forKey: .link)
    }
}

struct LivePlayInfoData: Decodable {
    let playurlInfo: LivePlayURLInfo?

    enum CodingKeys: String, CodingKey {
        case playurlInfo = "playurl_info"
    }

    var firstPlayableURL: URL? {
        playurlInfo?.playurl?.stream?
            .firstPlayableURL(preferHLS: true)
    }
}

struct LiveRoomPlayURLData: Decodable {
    let durl: [LiveRoomPlayURLItem]?

    var firstURL: URL? {
        durl?.compactMap { URL(string: $0.url) }.first
    }
}

struct LiveRoomPlayURLItem: Decodable {
    let url: String
}

struct LiveAnchorInfoData: Decodable, Hashable {
    let info: LiveAnchorProfile?
    let relationInfo: LiveAnchorRelationInfo?

    enum CodingKeys: String, CodingKey {
        case info
        case relationInfo = "relation_info"
    }
}

struct LiveAnchorProfile: Decodable, Hashable {
    let uid: Int?
    let uname: String?
    let face: String?
    let gender: String?

    enum CodingKeys: String, CodingKey {
        case uid, uname, face, gender
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = container.decodeLossyIntIfPresent(forKey: .uid)
        uname = try container.decodeIfPresent(String.self, forKey: .uname)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
    }
}

struct LiveAnchorRelationInfo: Decodable, Hashable {
    let attention: Int?

    enum CodingKeys: String, CodingKey {
        case attention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attention = container.decodeLossyIntIfPresent(forKey: .attention)
    }
}

struct FollowedLiveRoomsData: Decodable {
    let list: [LiveRoom]?
    let rooms: [LiveRoom]?

    enum CodingKeys: String, CodingKey {
        case list
        case rooms = "room_list"
    }

    var roomList: [LiveRoom] {
        list ?? rooms ?? []
    }
}

struct LivePlayURLInfo: Decodable {
    let playurl: LivePlayURL?
}

struct LivePlayURL: Decodable {
    let stream: [LiveStream]?
}

struct LiveStream: Decodable {
    let protocolName: String?
    let format: [LiveStreamFormat]?

    enum CodingKeys: String, CodingKey {
        case format
        case protocolName = "protocol_name"
    }
}

struct LiveStreamFormat: Decodable {
    let formatName: String?
    let codec: [LiveStreamCodec]?

    enum CodingKeys: String, CodingKey {
        case codec
        case formatName = "format_name"
    }
}

struct LiveStreamCodec: Decodable {
    let codecName: String?
    let currentQN: Int?
    let baseURL: String
    let urlInfo: [LiveStreamURLInfo]?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case currentQN = "current_qn"
        case baseURL = "base_url"
        case urlInfo = "url_info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codecName = try container.decodeIfPresent(String.self, forKey: .codecName)
        currentQN = container.decodeLossyIntIfPresent(forKey: .currentQN)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        urlInfo = try container.decodeIfPresent([LiveStreamURLInfo].self, forKey: .urlInfo)
    }

    var playableURLs: [URL] {
        if let urlInfo, !urlInfo.isEmpty {
            return urlInfo.compactMap { info in
                Self.makeURL(host: info.host, baseURL: baseURL, extra: info.extra)
            }
        }
        return Self.makeURL(host: "", baseURL: baseURL, extra: nil).map { [$0] } ?? []
    }

    private static func makeURL(host: String, baseURL: String, extra: String?) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }

        let normalizedHost: String
        if trimmedBase.hasPrefix("http://") || trimmedBase.hasPrefix("https://") {
            normalizedHost = ""
        } else if host.hasPrefix("//") {
            normalizedHost = "https:" + host
        } else {
            normalizedHost = host
        }

        var urlString = normalizedHost + trimmedBase
        if let extra, !extra.isEmpty {
            if urlString.hasSuffix("?") || urlString.hasSuffix("&") {
                urlString += extra.trimmingPrefixCharacters(["?", "&"])
            } else if extra.hasPrefix("?") || extra.hasPrefix("&") {
                urlString += extra
            } else {
                urlString += urlString.contains("?") ? "&\(extra)" : "?\(extra)"
            }
        }

        return URL(string: urlString)
    }
}

struct LiveStreamURLInfo: Decodable {
    let host: String
    let extra: String?
}

struct NavUserInfo: Decodable {
    let isLogin: Bool?
    let face: String?
    let uname: String?
    let mid: Int?
    let wbiImg: WBIImage?

    enum CodingKeys: String, CodingKey {
        case face, uname, mid
        case isLogin = "isLogin"
        case wbiImg = "wbi_img"
    }
}

struct WBIImage: Decodable {
    let imgURL: String
    let subURL: String

    enum CodingKeys: String, CodingKey {
        case imgURL = "img_url"
        case subURL = "sub_url"
    }
}

private extension Array where Element == LiveStream {
    func firstPlayableURL(preferHLS: Bool) -> URL? {
        let candidates = flatMap { stream in
            (stream.format ?? []).flatMap { format in
                (format.codec ?? []).map { codec in
                    (stream.protocolName ?? "", format.formatName ?? "", codec)
                }
            }
        }

        if preferHLS {
            let hls = candidates.first { protocolName, formatName, codec in
                protocolName.localizedCaseInsensitiveContains("hls")
                    || formatName.localizedCaseInsensitiveContains("ts")
                    || codec.baseURL.localizedCaseInsensitiveContains(".m3u8")
            }
            if let url = hls?.2.playableURLs.first {
                return url
            }
        }

        return candidates.flatMap { $0.2.playableURLs }.first
    }
}

private extension String {
    func trimmingPrefixCharacters(_ characters: Set<Character>) -> String {
        var result = self
        while let first = result.first, characters.contains(first) {
            result.removeFirst()
        }
        return result
    }
}

extension String {
    func normalizedBiliURL() -> String {
        if hasPrefix("//") {
            return "https:" + self
        }
        if hasPrefix("http://") {
            return replacingOccurrences(of: "http://", with: "https://")
        }
        return self
    }

    func biliCoverThumbnailURL(width: Int = 672, height: Int = 378) -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        return normalized.biliImageView2URL(width: width, height: height)
    }

    func biliAvatarThumbnailURL(size: Int = 96) -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        let pixelSize = max(48, size)
        return normalized.biliImageView2URL(width: pixelSize, height: pixelSize)
    }

    func biliImageThumbnailURL(maxSide: Int = 1080) -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        let pixelSize = min(max(96, maxSide), 4096)
        return "\(normalized.biliImageBaseURL())?imageView2/2/w/\(pixelSize)/format/webp"
    }

    private func biliImageView2URL(width: Int, height: Int) -> String {
        let base = biliImageBaseURL()
        return "\(base)?imageView2/2/w/\(width)/h/\(height)/format/webp"
    }

    private func biliImageBaseURL() -> String {
        let queryStart = firstIndex(of: "?") ?? endIndex
        var base = String(self[..<queryStart])
        let lastSlash = base.lastIndex(of: "/") ?? base.startIndex
        if let suffixStart = base[lastSlash...].firstIndex(of: "@") {
            base = String(base[..<suffixStart])
        }
        return base
    }

    func removingHTMLTags() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    nonisolated func decodeLossyStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(format: "%.3f", value)
        }
        return nil
    }

    nonisolated func decodeLossyBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

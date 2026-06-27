import CoreGraphics
import Foundation

enum BiliVideoQuality {
    nonisolated static let supportedQualities = [129, 127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]

    nonisolated static func title(for quality: Int?) -> String {
        guard let quality else { return "自动（快速开播）" }
        switch quality {
        case 129:
            return "HDR Vivid"
        case 127:
            return "8K"
        case 126:
            return "杜比视界"
        case 125:
            return "真彩 HDR"
        case 120:
            return "4K"
        case 116:
            return "1080P 高帧率"
        case 112:
            return "1080P 高码率"
        case 80:
            return "1080P"
        case 74:
            return "720P 高帧率"
        case 64:
            return "720P"
        case 32:
            return "480P"
        case 16:
            return "360P"
        case 6:
            return "240P"
        default:
            return "清晰度 \(quality)"
        }
    }

    nonisolated static func compactTitle(for quality: Int, fallback: String) -> String {
        switch quality {
        case 129:
            return "HDR Vivid"
        case 127:
            return "8K"
        case 126:
            return "杜比视界"
        case 125:
            return "HDR"
        case 120:
            return "4K"
        case 116:
            return "1080P60"
        case 112:
            return "1080P+"
        case 80:
            return "1080P"
        case 74:
            return "720P60"
        case 64:
            return "720P"
        case 32:
            return "480P"
        case 16:
            return "360P"
        case 6:
            return "240P"
        default:
            return fallback.isEmpty ? "清晰度 \(quality)" : fallback
        }
    }
}

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

nonisolated struct BiliResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let msg: String?
    let data: T?
    let result: T?

    nonisolated var payload: T? {
        data ?? result
    }

    nonisolated var displayMessage: String? {
        message ?? msg
    }
}

nonisolated struct BiliPage<T: Decodable>: Decodable {
    let list: [T]?
    let item: [T]?
    let result: [T]?
}

nonisolated struct VideoItem: Identifiable, Decodable, Hashable, Sendable {
    nonisolated var id: String { bvid }

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
    let historyResumeTime: TimeInterval?
    let historyCID: Int?
    let recommendReason: String?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, title, pic, desc, duration, pubdate, owner, stat, cid, pages, dimension
        case historyResumeTime, historyCID, recommendReason
    }

    init(
        bvid: String,
        aid: Int?,
        title: String,
        pic: String?,
        desc: String?,
        duration: Int?,
        pubdate: Int?,
        owner: VideoOwner?,
        stat: VideoStat?,
        cid: Int?,
        pages: [VideoPage]?,
        dimension: VideoDimension?,
        historyResumeTime: TimeInterval? = nil,
        historyCID: Int? = nil,
        recommendReason: String? = nil
    ) {
        self.bvid = bvid
        self.aid = aid
        self.title = title
        self.pic = pic
        self.desc = desc
        self.duration = duration
        self.pubdate = pubdate
        self.owner = owner
        self.stat = stat
        self.cid = cid
        self.pages = pages
        self.dimension = dimension
        self.historyResumeTime = historyResumeTime
        self.historyCID = historyCID
        self.recommendReason = recommendReason
    }

    nonisolated func mergingFilledValues(from fullDetail: VideoItem) -> VideoItem {
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
            dimension: fullDetail.dimension ?? dimension,
            historyResumeTime: historyResumeTime ?? fullDetail.historyResumeTime,
            historyCID: historyCID ?? fullDetail.historyCID,
            recommendReason: recommendReason ?? fullDetail.recommendReason
        )
    }
}

nonisolated struct VideoOwner: Decodable, Hashable, Sendable {
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

nonisolated struct VideoStat: Decodable, Hashable, Sendable {
    let view: Int?
    let reply: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?
}

nonisolated struct VideoPage: Identifiable, Decodable, Hashable {
    var id: Int { cid }

    let cid: Int
    let page: Int?
    let part: String?
    let duration: Int?
    let dimension: VideoDimension?
}

nonisolated struct VideoDimension: Decodable, Hashable {
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

nonisolated struct UploaderProfile: Decodable, Hashable {
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

nonisolated struct UploaderCard: Decodable, Hashable {
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

nonisolated struct UploaderVideoData: Decodable {
    let list: UploaderVideoList?
}

nonisolated struct UploaderVideoList: Decodable {
    let vlist: [UploaderVideoItem]?
}

nonisolated struct UploaderVideoItem: Decodable, Hashable {
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

nonisolated struct RecommendFeedData: Decodable, Sendable {
    let item: [RecommendFeedItem]?
    let items: [RecommendFeedItem]?
    let config: RecommendFeedConfig?

    nonisolated var feedItems: [RecommendFeedItem] {
        item ?? items ?? []
    }

    nonisolated func appNextIndex(after requestedIndex: Int) -> Int? {
        if let configIndex = config?.idx, configIndex > 0 {
            return configIndex
        }
        let positiveIndexes = feedItems.compactMap(\.idx).filter { $0 > 0 }
        if let lastIndex = positiveIndexes.last {
            return lastIndex
        }
        guard !feedItems.isEmpty else { return nil }
        return requestedIndex + 1
    }
}

nonisolated struct RecommendFeedConfig: Decodable, Hashable, Sendable {
    let idx: Int?

    enum CodingKeys: String, CodingKey {
        case idx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idx = container.decodeLossyIntIfPresent(forKey: .idx)
    }
}

nonisolated struct RecommendFeedReason: Decodable, Hashable, Sendable {
    let content: String?

    enum CodingKeys: String, CodingKey {
        case content, text, reason
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            content = value
            return
        }

        let container = try? decoder.container(keyedBy: CodingKeys.self)
        content = container?.decodeLossyStringIfPresent(forKey: .content)
            ?? container?.decodeLossyStringIfPresent(forKey: .text)
            ?? container?.decodeLossyStringIfPresent(forKey: .reason)
    }
}

nonisolated struct RecommendFeedItem: Identifiable, Decodable, Hashable, Sendable {
    nonisolated var id: String { bvid ?? String(aid ?? 0) }

    let idValue: Int?
    let aid: Int?
    let bvid: String?
    let cid: Int?
    let title: String?
    let pic: String?
    let cover: String?
    let uri: String?
    let param: String?
    let goto: String?
    let cardGoto: String?
    let duration: Int?
    let pubdate: Int?
    let idx: Int?
    let owner: VideoOwner?
    let ownerInfo: VideoOwner?
    let args: RecommendFeedItemArgs?
    let descButton: RecommendFeedDescButton?
    let desc: String?
    let recommendReason: RecommendFeedReason?
    let bottomRecommendReason: RecommendFeedReason?
    let topRecommendReason: RecommendFeedReason?
    let stat: VideoStat?
    let dimension: VideoDimension?

    nonisolated var resolvedCardKind: String {
        goto ?? cardGoto ?? "-"
    }

    nonisolated var isVideoCard: Bool {
        let target = goto ?? cardGoto
        return target == nil || target == "av" || target == "video"
    }

    enum CodingKeys: String, CodingKey {
        case aid, bvid, cid, title, pic, cover, uri, param, goto, idx, duration, pubdate, ctime, owner, args, desc, stat, dimension
        case idValue = "id"
        case cardGoto = "card_goto"
        case ownerInfo = "owner_info"
        case descButton = "desc_button"
        case recommendReason = "rcmd_reason"
        case bottomRecommendReason = "bottom_rcmd_reason"
        case topRecommendReason = "top_rcmd_reason"
        case pubDate = "pub_date"
        case publishTime = "publish_time"
        case coverLeftText1 = "cover_left_text_1"
        case coverLeftText2 = "cover_left_text_2"
        case coverRightText = "cover_right_text"
        case playerArgs = "player_args"
    }

    enum PlayerArgsCodingKeys: String, CodingKey {
        case aid
        case cid
        case duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let playerArgs = try? container.nestedContainer(keyedBy: PlayerArgsCodingKeys.self, forKey: .playerArgs)
        idValue = container.decodeLossyIntIfPresent(forKey: .idValue)
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
            ?? playerArgs?.decodeLossyIntIfPresent(forKey: .aid)
            ?? container.decodeLossyIntIfPresent(forKey: .param)
        bvid = container.decodeLossyStringIfPresent(forKey: .bvid)
        cid = container.decodeLossyIntIfPresent(forKey: .cid)
            ?? playerArgs?.decodeLossyIntIfPresent(forKey: .cid)
        title = container.decodeLossyStringIfPresent(forKey: .title)
        pic = container.decodeLossyStringIfPresent(forKey: .pic)
        cover = container.decodeLossyStringIfPresent(forKey: .cover)
        uri = container.decodeLossyStringIfPresent(forKey: .uri)
        param = container.decodeLossyStringIfPresent(forKey: .param)
        goto = container.decodeLossyStringIfPresent(forKey: .goto)
        cardGoto = container.decodeLossyStringIfPresent(forKey: .cardGoto)
        idx = container.decodeLossyIntIfPresent(forKey: .idx)
        duration = container.decodeLossyIntIfPresent(forKey: .duration)
            ?? playerArgs?.decodeLossyIntIfPresent(forKey: .duration)
            ?? Self.durationSeconds(from: container.decodeLossyStringIfPresent(forKey: .coverRightText))
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
            ?? container.decodeLossyIntIfPresent(forKey: .pubDate)
            ?? container.decodeLossyIntIfPresent(forKey: .publishTime)
            ?? container.decodeLossyIntIfPresent(forKey: .ctime)
        owner = try container.decodeIfPresent(VideoOwner.self, forKey: .owner)
        ownerInfo = try container.decodeIfPresent(VideoOwner.self, forKey: .ownerInfo)
        args = try container.decodeIfPresent(RecommendFeedItemArgs.self, forKey: .args)
        descButton = try container.decodeIfPresent(RecommendFeedDescButton.self, forKey: .descButton)
        desc = container.decodeLossyStringIfPresent(forKey: .desc)
        recommendReason = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .recommendReason)
        bottomRecommendReason = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .bottomRecommendReason)
        topRecommendReason = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .topRecommendReason)
        stat = (try container.decodeIfPresent(VideoStat.self, forKey: .stat))
            ?? Self.stat(from: container.decodeLossyStringIfPresent(forKey: .coverLeftText1))
            ?? Self.stat(from: container.decodeLossyStringIfPresent(forKey: .coverLeftText2))
        dimension = try container.decodeIfPresent(VideoDimension.self, forKey: .dimension)
    }

    nonisolated func asVideoItem() -> VideoItem? {
        guard isVideoCard else { return nil }
        guard let title,
              let identity = Self.videoIdentity(bvid: bvid, uri: uri, aid: idValue ?? aid)
        else { return nil }
        return VideoItem(
            bvid: identity.bvid,
            aid: idValue ?? aid,
            title: title,
            pic: (pic ?? cover)?.normalizedBiliURL(),
            desc: desc,
            duration: duration,
            pubdate: pubdate,
            owner: owner ?? ownerInfo ?? args?.owner ?? descButton?.owner,
            stat: stat,
            cid: cid,
            pages: nil,
            dimension: dimension,
            recommendReason: sanitizedRecommendReason
        )
    }

    private nonisolated var sanitizedRecommendReason: String? {
        let value = [
            recommendReason?.content,
            bottomRecommendReason?.content,
            topRecommendReason?.content
        ]
        .compactMap { raw -> String? in
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  !Self.hiddenRecommendReasons.contains(trimmed)
            else { return nil }
            return trimmed
        }
        .first
        return value
    }

    private nonisolated static let hiddenRecommendReasons: Set<String> = ["已关注", "新关注"]

    private nonisolated static func videoIdentity(bvid: String?, uri: String?, aid: Int?) -> (bvid: String, isSynthetic: Bool)? {
        if let bvid, !bvid.isEmpty {
            return (bvid, false)
        }
        if let bvid = Self.bvid(from: uri) {
            return (bvid, false)
        }
        guard let aid, aid > 0 else { return nil }
        return ("av\(aid)", true)
    }

    private nonisolated static func bvid(from uri: String?) -> String? {
        guard let uri, !uri.isEmpty else { return nil }
        if let range = uri.range(of: #"BV[A-Za-z0-9]+"#, options: .regularExpression) {
            return String(uri[range])
        }
        return nil
    }

    private nonisolated static func stat(from text: String?) -> VideoStat? {
        guard let view = compactCountValue(from: text) else { return nil }
        return VideoStat(view: view, reply: nil, like: nil, coin: nil, favorite: nil)
    }

    private nonisolated static func compactCountValue(from text: String?) -> Int? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "播放", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if normalized.hasSuffix("万"),
           let value = Double(normalized.dropLast()) {
            return Int((value * 10_000).rounded())
        }
        if normalized.hasSuffix("亿"),
           let value = Double(normalized.dropLast()) {
            return Int((value * 100_000_000).rounded())
        }
        return Int(normalized)
    }

    private nonisolated static func durationSeconds(from text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2:
            return parts[0] * 60 + parts[1]
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }
}

nonisolated struct RecommendFeedItemArgs: Decodable, Hashable, Sendable {
    let upID: Int?
    let upName: String?
    let upFace: String?

    enum CodingKeys: String, CodingKey {
        case upID = "up_id"
        case upMID = "up_mid"
        case mid
        case uid
        case upName = "up_name"
        case uname
        case name
        case author
        case upFace = "up_face"
        case face
        case avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upID = container.decodeLossyIntIfPresent(forKey: .upID)
            ?? container.decodeLossyIntIfPresent(forKey: .upMID)
            ?? container.decodeLossyIntIfPresent(forKey: .mid)
            ?? container.decodeLossyIntIfPresent(forKey: .uid)
        upName = container.decodeLossyStringIfPresent(forKey: .upName)
            ?? container.decodeLossyStringIfPresent(forKey: .uname)
            ?? container.decodeLossyStringIfPresent(forKey: .name)
            ?? container.decodeLossyStringIfPresent(forKey: .author)
        upFace = container.decodeLossyStringIfPresent(forKey: .upFace)
            ?? container.decodeLossyStringIfPresent(forKey: .face)
            ?? container.decodeLossyStringIfPresent(forKey: .avatar)
    }

    nonisolated var owner: VideoOwner? {
        guard upID != nil || upName != nil || upFace != nil else { return nil }
        let trimmedName = upName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VideoOwner(
            mid: upID ?? 0,
            name: trimmedName?.isEmpty == false ? trimmedName! : "Unknown",
            face: upFace?.normalizedBiliURL()
        )
    }
}

nonisolated struct RecommendFeedDescButton: Decodable, Hashable, Sendable {
    let text: String?
    let uri: String?

    enum CodingKeys: String, CodingKey {
        case text, uri
    }

    nonisolated var owner: VideoOwner? {
        let trimmedName = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mid = Self.mid(from: uri)
        guard mid != nil || trimmedName?.isEmpty == false else { return nil }
        return VideoOwner(
            mid: mid ?? 0,
            name: trimmedName?.isEmpty == false ? trimmedName! : "Unknown",
            face: nil
        )
    }

    private nonisolated static func mid(from uri: String?) -> Int? {
        guard let uri, !uri.isEmpty else { return nil }
        if let range = uri.range(of: #"space/(\d+)"#, options: .regularExpression) {
            let value = uri[range].dropFirst("space/".count)
            return Int(value)
        }
        if let range = uri.range(of: #"vmid=(\d+)"#, options: .regularExpression) {
            let value = uri[range].dropFirst("vmid=".count)
            return Int(value)
        }
        return nil
    }
}

nonisolated struct PlayURLData: Decodable, Sendable {
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
        playVariants.contains(where: \.isPlayable)
    }

    nonisolated var hasAnyPlayURLPayload: Bool {
        durl?.contains(where: { $0.playURL != nil }) == true
            || dash?.video?.contains(where: { $0.playURL != nil }) == true
            || dash?.audio?.contains(where: { $0.playURL != nil }) == true
    }

    nonisolated var rawPlayURLSummary: String {
        let videoStreams = dash?.video ?? []
        let audioStreams = dash?.audio ?? []
        let hevcCount = videoStreams.filter(\.isHEVCVideoCodec).count
        let av1Count = videoStreams.filter(\.isAV1VideoCodec).count
        let avcCount = videoStreams.filter(\.isAVCVideoCodec).count
        let aacCount = audioStreams.filter(\.isAACAudioCodec).count
        return "dashVideo=\(videoStreams.count) hevc=\(hevcCount) av1=\(av1Count) avc=\(avcCount) dashAudio=\(audioStreams.count) aac=\(aacCount) durl=\(durl?.count ?? 0)"
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
        playVariants(cdnPreference: .automatic)
    }

    nonisolated func playVariants(cdnPreference: PlaybackCDNPreference) -> [PlayVariant] {
        playVariants(
            cdnPreference: cdnPreference,
            codecPreference: VideoCodecPreference.stored()
        )
    }

    nonisolated func playVariants(
        cdnPreference: PlaybackCDNPreference,
        codecPreference: VideoCodecPreference
    ) -> [PlayVariant] {
        let preferredKernel = PlayerKernelType.stored()
        let bestAudio = dash?.bestAudioStream
        let videosByQuality = Dictionary(grouping: dash?.video ?? [], by: { $0.id ?? 0 })
        let descriptions = Dictionary(uniqueKeysWithValues: zip(acceptQuality ?? [], acceptDescription ?? []))
        let supportByQuality = (supportFormats ?? []).reduce(into: [Int: PlaySupportFormat]()) { result, format in
            guard let quality = format.quality, result[quality] == nil else { return }
            result[quality] = format
        }
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
            let videoStreams = videosByQuality[quality] ?? []
            let streamCandidates = videoStreams.filter { stream in
                stream.isHardwareDecodingCompatibleVideo
            }
            let stream = DashStreamDispatcher.selectBestStream(
                from: streamCandidates,
                preference: codecPreference,
                kernel: preferredKernel
            )
            guard let stream,
                  let streamURL = stream.playURL(cdnPreference: cdnPreference),
                  let bestAudio,
                  let audioURL = bestAudio.playURL(cdnPreference: cdnPreference)
            else { continue }
            variants.append(PlayVariant(
                quality: quality,
                title: support?.title ?? descriptions[quality] ?? Self.qualityTitle(quality),
                videoURL: streamURL,
                audioURL: audioURL,
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

        for stream in dash?.video ?? [] where !variants.contains(where: { $0.quality == (stream.id ?? 0) }) {
            guard stream.isHardwareDecodingCompatibleVideo,
                  let streamURL = stream.playURL(cdnPreference: cdnPreference),
                  let bestAudio,
                  let audioURL = bestAudio.playURL(cdnPreference: cdnPreference)
            else { continue }
            let quality = stream.id ?? 0
            let support = supportByQuality[quality]
            variants.append(PlayVariant(
                quality: quality,
                title: support?.title ?? descriptions[quality] ?? Self.qualityTitle(quality),
                videoURL: streamURL,
                audioURL: audioURL,
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

        if let durl, !durl.isEmpty {
            let progressiveQuality = quality ?? orderedQualities.first ?? 0
            let support = supportByQuality[progressiveQuality]
            let title = support?.title ?? descriptions[progressiveQuality] ?? Self.qualityTitle(progressiveQuality)
            for item in durl {
                guard let streamURL = item.playURL(cdnPreference: cdnPreference),
                      !variants.contains(where: { $0.videoURL == streamURL })
                else { continue }
                variants.append(PlayVariant(
                    quality: progressiveQuality,
                    title: title,
                    videoURL: streamURL,
                    audioURL: nil,
                    videoStream: nil,
                    audioStream: nil,
                    codec: support?.codecLabel,
                    resolution: nil,
                    frameRate: nil,
                    bandwidth: nil,
                    isHDR: Self.isHDR(quality: progressiveQuality, title: support?.title ?? descriptions[progressiveQuality]),
                    badge: support?.badge
                ))
            }
        }

        appendAdvertisedLockedVariants(
            orderedQualities: orderedQualities,
            supportByQuality: supportByQuality,
            descriptions: descriptions,
            videosByQuality: videosByQuality,
            codecPreference: codecPreference,
            into: &variants
        )

        return variants
    }

    nonisolated private func appendAdvertisedLockedVariants(
        orderedQualities: [Int],
        supportByQuality: [Int: PlaySupportFormat],
        descriptions: [Int: String],
        videosByQuality: [Int: [DASHStream]],
        codecPreference: VideoCodecPreference,
        into variants: inout [PlayVariant]
    ) {
        let preferredKernel = PlayerKernelType.stored()
        for quality in orderedQualities {
            guard quality > 0,
                  !variants.contains(where: { $0.quality == quality })
            else { continue }

            let support = supportByQuality[quality]
            let representativeStream = DashStreamDispatcher.selectBestStream(
                from: videosByQuality[quality] ?? [],
                preference: codecPreference,
                kernel: preferredKernel
            )
            variants.append(PlayVariant(
                quality: quality,
                title: support?.title ?? descriptions[quality] ?? Self.qualityTitle(quality),
                videoURL: nil,
                audioURL: nil,
                videoStream: representativeStream,
                audioStream: nil,
                codec: representativeStream?.codecLabel ?? support?.codecLabel,
                resolution: representativeStream?.resolutionLabel,
                frameRate: representativeStream?.frameRate,
                bandwidth: representativeStream?.bandwidth,
                isHDR: Self.isHDR(quality: quality, title: support?.title ?? descriptions[quality]),
                badge: support?.badge
            ))
        }
    }

    nonisolated private static func qualityTitle(_ quality: Int) -> String {
        BiliVideoQuality.title(for: quality)
    }

    nonisolated private static func isHDR(quality: Int, title: String?) -> Bool {
        quality == 129
            || quality == 125
            || quality == 126
            || title?.localizedCaseInsensitiveContains("HDR") == true
            || title?.localizedCaseInsensitiveContains("Vivid") == true
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

nonisolated struct PlayVariant: Identifiable, Hashable, Sendable {
    nonisolated var id: String {
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
        videoURL != nil
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
        audioURL == nil && videoStream == nil
    }

    nonisolated func replacingPlaybackURLs(videoURL: URL?, audioURL: URL?) -> PlayVariant {
        PlayVariant(
            quality: quality,
            title: title,
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: videoStream,
            audioStream: audioStream,
            codec: codec,
            resolution: resolution,
            frameRate: frameRate,
            bandwidth: bandwidth,
            isHDR: isHDR,
            badge: badge
        )
    }

    nonisolated var videoAspectRatio: Double? {
        if let videoStream,
           let width = videoStream.width,
           let height = videoStream.height,
           width > 0,
           height > 0 {
            return Double(width) / Double(height)
        }
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
        if quality == 129 || title.localizedCaseInsensitiveContains("Vivid") {
            return "HDR Vivid"
        }
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
            parts.append(unavailableReason)
        }
        return parts.joined(separator: " · ")
    }

    nonisolated var qualityMenuTitle: String {
        let title = BiliVideoQuality.title(for: quality)
        guard !isPlayable else { return title }
        return "\(title)（\(unavailableReason)）"
    }

    nonisolated var compactAccessoryTitle: String {
        let normalizedTitle = title.replacingOccurrences(of: " ", with: "")
        return BiliVideoQuality.compactTitle(for: quality, fallback: normalizedTitle)
    }

    nonisolated private var unavailableReason: String {
        if let videoStream, !videoStream.isHardwareDecodingCompatibleVideo {
            return "当前设备暂不可播"
        }
        return "需要登录或权限"
    }

    nonisolated private var playbackExperienceLabel: String? {
        switch quality {
        case 116, 74:
            return "流畅优先"
        case 112:
            return "细节优先"
        default:
            break
        }
        if let frameRate = DASHStream.numericFrameRate(from: frameRate), frameRate >= 50 {
            return "流畅优先"
        }
        return nil
    }

    nonisolated private var dynamicRangeMenuLabel: String? {
        guard let qualityBadge,
              !title.localizedCaseInsensitiveContains(qualityBadge)
        else { return nil }
        return qualityBadge
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

nonisolated struct PlaySupportFormat: Decodable, Sendable {
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

nonisolated struct PlayDURL: Decodable, Sendable {
    let url: String
    let backupURL: [String]?

    enum CodingKeys: String, CodingKey {
        case url
        case backupURL = "backup_url"
    }

    nonisolated var playURL: URL? {
        playURL(cdnPreference: .automatic)
    }

    nonisolated func playURL(cdnPreference: PlaybackCDNPreference) -> URL? {
        let primary = URL(string: url)
        let backups = backupURL?.compactMap(URL.init(string:)) ?? []
        return cdnPreference.preferredURLs(primary: primary, backups: backups).primary
    }
}

nonisolated struct DASHInfo: Decodable, Sendable {
    let duration: Int?
    let video: [DASHStream]?
    let audio: [DASHStream]?

    nonisolated var bestAudioStream: DASHStream? {
        audio?
            .filter(\.isHardwareDecodingCompatibleAudio)
            .sorted { lhs, rhs in
                if lhs.isAACAudioCodec != rhs.isAACAudioCodec {
                    return lhs.isAACAudioCodec && !rhs.isAACAudioCodec
                }
                return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
            }
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

nonisolated struct DASHStream: Decodable, Hashable, Sendable {
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
        playURL(cdnPreference: .automatic)
    }

    nonisolated func playURL(cdnPreference: PlaybackCDNPreference) -> URL? {
        let primary = URL(string: baseURL)
        return cdnPreference.preferredURLs(primary: primary, backups: backupPlayURLs).primary
    }

    nonisolated var backupPlayURLs: [URL] {
        backupURL?.compactMap(URL.init(string:)) ?? []
    }

    nonisolated func backupPlayURLs(cdnPreference: PlaybackCDNPreference) -> [URL] {
        let primary = URL(string: baseURL)
        return cdnPreference.preferredURLs(primary: primary, backups: backupPlayURLs).backups
    }

    nonisolated var codecLabel: String? {
        Self.codecLabel(for: codecs, codecid: codecid)
    }

    nonisolated var isHEVCVideoCodec: Bool {
        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("hvc1") || lowered.contains("hev1")
        }
        return codecid == 12
    }

    nonisolated var isAVCVideoCodec: Bool {
        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("avc1") || lowered.contains("avc3")
        }
        return codecid == 7
    }

    nonisolated var isAV1VideoCodec: Bool {
        if let codecs, !codecs.isEmpty {
            return codecs.lowercased().contains("av01")
        }
        return codecid == 13
    }

    nonisolated var isAACAudioCodec: Bool {
        guard let codecs, !codecs.isEmpty else {
            // Bilibili occasionally omits audio codec metadata on DASH audio
            // tracks that are still mp4a in practice; keep those eligible so
            // the HLS bridge can advertise the conservative AAC default.
            return true
        }
        return codecs.lowercased().contains("mp4a")
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
        if isHEVCVideoCodec {
            return PlaybackCodecPolicy.canDecodeHEVC
        }

        if PlaybackCodecPolicy.requiresHEVCPlayback,
           !PlaybackCodecPolicy.allowsNonHEVCHardwareFallback {
            return false
        }

        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("avc1")
                || lowered.contains("avc3")
                || (PlaybackCodecPolicy.canDecodeAV1 && lowered.contains("av01"))
                || lowered.contains("dvh1")
                || lowered.contains("dvhe")
        }

        switch codecid {
        case 7:
            return true
        case 13:
            return PlaybackCodecPolicy.canDecodeAV1
        default:
            return false
        }
    }

    nonisolated var isHardwareDecodingCompatibleAudio: Bool {
        if PlaybackCodecPolicy.requiresAACAudioPlayback {
            return isAACAudioCodec
        }

        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("mp4a")
                || lowered.contains("alac")
                || lowered.contains("ac-3")
                || lowered.contains("ec-3")
                || lowered.contains("opus")
        }
        return true
    }

    nonisolated static func displayFrameRate(from rawValue: String?) -> String? {
        guard let value = numericFrameRate(from: rawValue) else {
            guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        return formatFrameRate(value)
    }

    nonisolated static func numericFrameRate(from rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = Double(trimmed) {
            return value
        }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2,
           let numerator = Double(parts[0]),
           let denominator = Double(parts[1]),
           denominator != 0 {
            return numerator / denominator
        }

        return nil
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

nonisolated struct DASHSegmentBase: Decodable, Hashable, Sendable {
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

nonisolated struct HTTPByteRange: Hashable, Sendable {
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

nonisolated struct CommentPage: Decodable {
    let replies: [Comment]?
    let topReplies: [Comment]?
    let cursor: CommentCursor?

    enum CodingKeys: String, CodingKey {
        case replies, cursor
        case topReplies = "top_replies"
    }
}

nonisolated struct CommentCursor: Decodable {
    let next: String?
    let nextOffset: String?
    let isEnd: Bool?

    var effectiveNext: String? {
        Self.nonEmpty(next) ?? Self.nonEmpty(nextOffset)
    }

    enum CodingKeys: String, CodingKey {
        case next
        case nextOffset = "next_offset"
        case isEnd = "is_end"
        case paginationReply = "pagination_reply"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        next = container.decodeLossyStringIfPresent(forKey: .next)
        let nestedPagination = try? container.decodeIfPresent(CommentCursorPaginationReply.self, forKey: .paginationReply)
        nextOffset = container.decodeLossyStringIfPresent(forKey: .nextOffset)
            ?? nestedPagination?.nextOffset
        isEnd = container.decodeLossyBoolIfPresent(forKey: .isEnd)
            ?? nestedPagination?.isEnd
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated private struct CommentCursorPaginationReply: Decodable {
    let nextOffset: String?
    let isEnd: Bool?

    enum CodingKeys: String, CodingKey {
        case nextOffset = "next_offset"
        case isEnd = "is_end"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextOffset = container.decodeLossyStringIfPresent(forKey: .nextOffset)
        isEnd = container.decodeLossyBoolIfPresent(forKey: .isEnd)
    }
}

nonisolated struct Comment: Identifiable, Decodable, Hashable {
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

nonisolated struct CommentMember: Decodable, Hashable {
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

nonisolated struct CommentLevelInfo: Decodable, Hashable {
    let currentLevel: Int?

    enum CodingKeys: String, CodingKey {
        case currentLevel = "current_level"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentLevel = container.decodeLossyIntIfPresent(forKey: .currentLevel)
    }
}

nonisolated struct CommentContent: Decodable, Hashable {
    let message: String?
    let emotes: [String: CommentEmote]
    let pictures: [DynamicImageItem]
    let jumpURLs: DynamicJSONValue?
    let mentions: [BiliMention]
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
        mentions = BiliMentionExtractor.commentMentions(raw: raw, message: message, jumpURLs: jumpURLs)
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

nonisolated struct CommentEmote: Decodable, Hashable {
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

nonisolated struct AccountVideoEntry: Identifiable, Hashable {
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
            dimension: nil,
            historyResumeTime: resumeTime,
            historyCID: cid
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

nonisolated struct VideoHistoryProgress: Decodable, Hashable {
    let progress: TimeInterval?
    let lastPlayCid: Int?

    enum CodingKeys: String, CodingKey {
        case progress
        case lastPlayCid = "last_play_cid"
        case cid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progress = container.decodeLossyDoubleIfPresent(forKey: .progress)
        lastPlayCid = container.decodeLossyIntIfPresent(forKey: .lastPlayCid)
            ?? container.decodeLossyIntIfPresent(forKey: .cid)
    }

    func resumeTime(duration: TimeInterval?) -> TimeInterval? {
        guard let progress, progress >= 10 else { return nil }
        if let duration, duration > 0 {
            let remaining = duration - progress
            guard remaining > 15, progress / duration < 0.96 else { return nil }
        }
        return progress
    }
}

nonisolated struct SearchTypeData<Result: Decodable>: Decodable {
    let result: [Result]?
}

nonisolated struct SearchVideoItem: Identifiable, Decodable, Hashable {
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

nonisolated struct SearchUserItem: Identifiable, Decodable, Hashable {
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

nonisolated struct SearchUserOfficialVerify: Decodable, Hashable {
    let desc: String?
}

nonisolated struct SearchMediaItem: Identifiable, Decodable, Hashable {
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

nonisolated struct SearchMediaRating: Decodable, Hashable {
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

nonisolated struct SearchArticleItem: Identifiable, Decodable, Hashable {
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

nonisolated struct SearchSuggestResponse: Decodable {
    let tag: [SearchSuggestItem]?
}

nonisolated struct SearchSuggestItem: Identifiable, Decodable, Hashable {
    var id: String { value }

    let value: String
    let ref: Int?
}

nonisolated struct HotSearchData: Decodable {
    let trending: HotSearchTrending?
}

nonisolated struct HotSearchTrending: Decodable {
    let list: [HotSearchItem]?
}

nonisolated struct HotSearchItem: Identifiable, Decodable, Hashable {
    var id: String { keyword }

    let keyword: String
    let showName: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case keyword, icon
        case showName = "show_name"
    }
}

nonisolated struct EmptyBiliPayload: Decodable {}

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

nonisolated struct FavoriteFolderListData: Decodable, Hashable {
    let list: [FavoriteFolder]?
}

nonisolated struct FavoriteFolder: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String?
    let favState: Int?
    let mediaCount: Int?
    let cover: String?
    let intro: String?
    let attr: Int?
    let state: Int?
    let ctime: Int?
    let mtime: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, cover, intro, attr, state, ctime, mtime
        case mediaID = "media_id"
        case favState = "fav_state"
        case mediaCount = "media_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id)
            ?? container.decodeLossyIntIfPresent(forKey: .mediaID)
            ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        favState = container.decodeLossyIntIfPresent(forKey: .favState)
        mediaCount = container.decodeLossyIntIfPresent(forKey: .mediaCount)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        attr = container.decodeLossyIntIfPresent(forKey: .attr)
        state = container.decodeLossyIntIfPresent(forKey: .state)
        ctime = container.decodeLossyIntIfPresent(forKey: .ctime)
        mtime = container.decodeLossyIntIfPresent(forKey: .mtime)
    }

    var displayTitle: String {
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle?.isEmpty == false ? normalizedTitle! : "未命名收藏夹"
    }

    var isFavorited: Bool {
        favState == 1
    }
}

nonisolated private func firstNonBlankDynamicText(_ values: [String?]) -> String? {
    values
        .compactMap { $0?.removingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
}

nonisolated private func joinedDynamicText(_ values: [String?], separator: String = "") -> String? {
    let text = values
        .compactMap { $0?.removingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: separator)
    return text.isEmpty ? nil : text
}

nonisolated struct BiliMention: Hashable, Sendable {
    let text: String
    let mid: Int?
    let url: String?

    init?(text: String?, mid: Int? = nil, url: String? = nil) {
        guard let displayText = Self.normalizedDisplayText(text) else { return nil }
        let resolvedMID = mid ?? Self.userMID(in: url)
        self.text = displayText
        self.mid = resolvedMID
        let normalizedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = normalizedURL?.isEmpty == false ? normalizedURL : nil
    }

    var name: String {
        text.hasPrefix("@") ? String(text.dropFirst()) : text
    }

    var destinationURL: URL? {
        if let mid, mid > 0 {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "space.bilibili.com"
            components.path = "/\(mid)"
            if !name.isEmpty {
                components.queryItems = [URLQueryItem(name: "name", value: name)]
            }
            return components.url
        }

        guard let url else { return nil }
        let normalized = url.normalizedBiliURL()
        if let mid = Self.userMID(in: normalized), mid > 0 {
            return URL(string: "https://space.bilibili.com/\(mid)")
        }
        return URL(string: normalized)
    }

    private static func normalizedDisplayText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .removingHTMLTags()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:"))
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }

    static func userMID(in rawURL: String?) -> Int? {
        guard let rawURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty
        else { return nil }

        let normalized = rawURL.normalizedBiliURL()
        if let components = URLComponents(string: normalized) {
            if let queryMID = components.queryItems?.first(where: {
                ["mid", "uid", "vmid"].contains($0.name.lowercased())
            })?.value.flatMap(Int.init) {
                return queryMID
            }

            let host = components.host?.lowercased()
            let pathID = components.path
                .split(separator: "/")
                .compactMap { Int($0) }
                .first
            if host == "space.bilibili.com" || host == "space" {
                return pathID
            }
        }

        let patterns = [
            #"(?i)space\.bilibili\.com/(\d+)"#,
            #"(?i)bilibili://space/(\d+)"#,
            #"(?i)(?:^|[?&])(?:mid|uid|vmid)=(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  let matchRange = Range(match.range(at: 1), in: normalized)
            else { continue }
            if let mid = Int(normalized[matchRange]) {
                return mid
            }
        }
        return nil
    }
}

nonisolated enum BiliMentionExtractor {
    static func commentMentions(
        raw: DynamicJSONValue?,
        message _: String?,
        jumpURLs: DynamicJSONValue?
    ) -> [BiliMention] {
        unique(mentions(in: raw, context: .commentRoot) + mentions(in: jumpURLs, context: .jumpURLs))
    }

    static func richTextMention(
        object: [String: DynamicJSONValue],
        type: String?,
        text: String?
    ) -> BiliMention? {
        guard isMentionType(type) else { return nil }
        let url = firstText([
            object["jump_url"],
            object["jumpUrl"],
            object["url"],
            object["uri"],
            object["link"]
        ])
        let mid = firstInt([
            object["rid"],
            object["mid"],
            object["uid"],
            object["user_id"],
            object["user_mid"],
            object["vmid"]
        ]) ?? BiliMention.userMID(in: url)
        let mentionText = firstNonBlankDynamicText([
            text,
            textValue(object["orig_text"]),
            textValue(object["text"]),
            textValue(object["name"]),
            textValue(object["uname"])
        ])
        return BiliMention(text: mentionText, mid: mid, url: url)
    }

    private enum Context {
        case commentRoot
        case jumpURLs
        case memberList
        case nested
    }

    private static func mentions(in value: DynamicJSONValue?, context: Context) -> [BiliMention] {
        guard let value else { return [] }
        switch value {
        case .array(let values):
            return unique(values.flatMap { mentions(in: $0, context: context == .jumpURLs ? .jumpURLs : .memberList) })
        case .object(let object):
            var result = [BiliMention]()
            result.append(contentsOf: mentionsFromNameToMIDMaps(object))

            for (key, child) in object where key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") {
                let url = firstNavigationalText(in: child)
                let mid = firstMID(in: child) ?? BiliMention.userMID(in: url)
                if let mention = BiliMention(text: key, mid: mid, url: url) {
                    result.append(mention)
                }
            }

            if context == .memberList,
               let mention = mentionObject(object) {
                result.append(mention)
            }

            for key in ["members", "member", "at_members", "atMembers", "users", "user", "jump_url", "jump_urls", "jumpURL", "jumpURLs"] {
                guard let child = object[key] else { continue }
                let childContext: Context = key.lowercased().contains("jump") ? .jumpURLs : .memberList
                result.append(contentsOf: mentions(in: child, context: childContext))
            }

            if context == .jumpURLs || context == .nested {
                for child in object.values {
                    result.append(contentsOf: mentions(in: child, context: .nested))
                }
            }

            return unique(result)
        case .string, .number, .bool, .null:
            return []
        }
    }

    private static func mentionsFromNameToMIDMaps(_ object: [String: DynamicJSONValue]) -> [BiliMention] {
        let keys = [
            "at_name_to_mid",
            "atNameToMid",
            "at_name_to_mid_map",
            "atNameToMidMap"
        ]
        return keys.flatMap { key -> [BiliMention] in
            guard case .object(let map)? = object[key] else { return [] }
            return map.compactMap { name, value in
                BiliMention(text: name, mid: intValue(value))
            }
        }
    }

    private static func mentionObject(_ object: [String: DynamicJSONValue]) -> BiliMention? {
        let url = firstText([
            object["jump_url"],
            object["jumpUrl"],
            object["space_url"],
            object["spaceUrl"],
            object["url"],
            object["uri"],
            object["link"]
        ])
        let mid = firstInt([
            object["mid"],
            object["uid"],
            object["user_id"],
            object["user_mid"],
            object["vmid"],
            object["rid"]
        ]) ?? BiliMention.userMID(in: url)
        let text = firstNonBlankDynamicText([
            textValue(object["uname"]),
            textValue(object["name"]),
            textValue(object["nickname"]),
            textValue(object["text"]),
            textValue(object["orig_text"])
        ])

        guard mid != nil || text?.hasPrefix("@") == true || BiliMention.userMID(in: url) != nil else {
            return nil
        }
        return BiliMention(text: text, mid: mid, url: url)
    }

    private static func firstMID(in value: DynamicJSONValue) -> Int? {
        switch value {
        case .object(let object):
            return firstInt([
                object["mid"],
                object["uid"],
                object["user_id"],
                object["user_mid"],
                object["vmid"],
                object["rid"]
            ]) ?? BiliMention.userMID(in: firstNavigationalText(in: value))
        case .array(let values):
            return values.lazy.compactMap(firstMID).first
        case .string(let string), .number(let string):
            return BiliMention.userMID(in: string)
        case .bool, .null:
            return nil
        }
    }

    private static func firstNavigationalText(in value: DynamicJSONValue) -> String? {
        switch value {
        case .string(let string), .number(let string):
            return string
        case .array(let values):
            return values.lazy.compactMap(firstNavigationalText).first
        case .object(let object):
            let preferred = firstText([
                object["jump_url"],
                object["jumpUrl"],
                object["space_url"],
                object["spaceUrl"],
                object["url"],
                object["uri"],
                object["link"],
                object["native_url"],
                object["raw_url"]
            ])
            if let preferred {
                return preferred
            }
            return object.values.lazy.compactMap(firstNavigationalText).first
        case .bool, .null:
            return nil
        }
    }

    private static func firstText(_ values: [DynamicJSONValue?]) -> String? {
        firstNonBlankDynamicText(values.map(textValue))
    }

    private static func firstInt(_ values: [DynamicJSONValue?]) -> Int? {
        values.lazy.compactMap(intValue).first
    }

    private static func textValue(_ value: DynamicJSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let string), .number(let string):
            return string
        case .bool, .array, .object, .null:
            return nil
        }
    }

    private static func intValue(_ value: DynamicJSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .string(let string), .number(let string):
            return Int(string)
        case .bool(let bool):
            return bool ? 1 : 0
        case .array, .object, .null:
            return nil
        }
    }

    private static func isMentionType(_ type: String?) -> Bool {
        guard let type else { return false }
        return type.uppercased().contains("AT")
    }

    private static func unique(_ mentions: [BiliMention]) -> [BiliMention] {
        var seen = Set<String>()
        var result = [BiliMention]()
        for mention in mentions {
            let key = "\(mention.text)|\(mention.mid.map(String.init) ?? "")|\(mention.url ?? "")"
            guard seen.insert(key).inserted else { continue }
            result.append(mention)
        }
        return result
    }
}

nonisolated enum DynamicTextSegment: Hashable {
    case text(String)
    case emoji(text: String, url: String?)
    case link(title: String, url: String)
    case mention(text: String, mid: Int?, url: String?)

    var displayText: String {
        switch self {
        case .text(let text):
            return text
        case .emoji(let text, _):
            return text
        case .link:
            return "查看链接"
        case .mention(let text, _, _):
            return text
        }
    }

    static func displayText(from segments: [DynamicTextSegment]) -> String? {
        firstNonBlankDynamicText([segments.map(\.displayText).joined()])
    }
}

nonisolated private func firstNonEmptyDynamicSegments(_ values: [[DynamicTextSegment]]) -> [DynamicTextSegment] {
    values.first { segments in
        DynamicTextSegment.displayText(from: segments)?.isEmpty == false
    } ?? []
}

nonisolated private func normalizedDynamicSegments(_ segments: [DynamicTextSegment]) -> [DynamicTextSegment] {
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
        case .mention(let text, let mid, let url):
            guard !text.isEmpty else { continue }
            result.append(.mention(text: text, mid: mid, url: url))
        }
    }
    return result
}

nonisolated private func dynamicPlainTextSegments(_ text: String?) -> [DynamicTextSegment] {
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

nonisolated private func normalizedOpenDynamicURL(_ raw: String?) -> String? {
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

nonisolated private func dynamicURLByTrimmingTrailingPunctuation(_ raw: String) -> (url: String, trailing: String) {
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

nonisolated private func shouldRenderDynamicLinkNode(type: String?, url: String?) -> Bool {
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

nonisolated private func uniqueDynamicImages(_ groups: [[DynamicImageItem]]) -> [DynamicImageItem] {
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
    nonisolated static let dynamicAdKeywords = [
        "领券",
        "满减",
        "美团",
        "清仓",
        "热卖",
        "闪购",
        "神券",
        "手淘",
        "淘宝",
        "推广",
        "下单",
        "转转",
        "按摩仪",
        "拼多多",
        "优惠券",
        "百亿补贴",
        "长按复制",
        "全网最低",
        "券后价格",
        "手机京东",
        "长按copy",
        "长按Fu制",
        "全网zui低"
    ]

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

    nonisolated static func isDynamicAdCandidateType(_ type: String?) -> Bool {
        guard let type else { return false }
        switch type.uppercased() {
        case "DYNAMIC_TYPE_DRAW", "DYNAMIC_TYPE_WORD", "DYNAMIC_TYPE_ARTICLE":
            return true
        default:
            return false
        }
    }

    nonisolated static func isDynamicAdText(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return dynamicAdKeywords.contains { keyword in
            text.range(
                of: keyword,
                options: [.caseInsensitive, .widthInsensitive]
            ) != nil
        }
    }
}

nonisolated private struct DynamicCodingKey: CodingKey {
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

nonisolated enum DynamicJSONValue: Codable, Hashable {
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

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value), .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in object {
                if let codingKey = DynamicCodingKey(stringValue: key) {
                    try container.encode(value, forKey: codingKey)
                }
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
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

            if let mention = BiliMentionExtractor.richTextMention(object: object, type: type, text: text) {
                return [.mention(text: mention.text, mid: mention.mid, url: mention.url)]
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

    var dynamicMajorFallbackArchive: DynamicArchive? {
        switch self {
        case .object(let object):
            for key in ["common", "ugc_season", "medialist", "archive", "video"] {
                if let archive = object[key]?.dynamicVideoArchiveCandidate {
                    return archive
                }
            }
            return dynamicVideoArchiveCandidate
        case .array(let values):
            return values.lazy.compactMap(\.dynamicMajorFallbackArchive).first
        case .string, .number, .bool, .null:
            return nil
        }
    }

    var dynamicMajorFallbackLive: DynamicLive? {
        switch self {
        case .object(let object):
            for key in ["live", "live_rcmd", "common", "additional"] {
                guard let data = try? JSONEncoder().encode(object[key]) else { continue }
                if let live = try? JSONDecoder().decode(DynamicLive.self, from: data),
                   live.hasLiveIdentity {
                    return live
                }
            }
            return nil
        case .array(let values):
            return values.lazy.compactMap(\.dynamicMajorFallbackLive).first
        case .string, .number, .bool, .null:
            return nil
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

    private var dynamicVideoArchiveCandidate: DynamicArchive? {
        guard case .object(let object) = self else { return nil }
        return DynamicArchive(fallbackObject: object)
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
            width: firstDynamicInt([
                object["width"],
                object["img_width"],
                object["image_width"],
                object["w"]
            ]),
            height: firstDynamicInt([
                object["height"],
                object["img_height"],
                object["image_height"],
                object["h"]
            ]),
            size: firstDynamicDouble([
                object["size"],
                object["img_size"],
                object["image_size"]
            ])
        )
    }

    private func firstDynamicInt(_ values: [DynamicJSONValue?]) -> Int? {
        values.lazy.compactMap(\.?.intValue).first
    }

    private func firstDynamicDouble(_ values: [DynamicJSONValue?]) -> Double? {
        values.lazy.compactMap(\.?.doubleValue).first
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

nonisolated private struct DynamicDiscardedValue: Decodable {}

nonisolated struct DynamicFeedData: Decodable, Hashable {
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

nonisolated struct DynamicFeedItem: Identifiable, Decodable, Hashable {
    nonisolated var id: String { idStr }

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
        modules?.moduleDynamic?.major?.resolvedArchive
    }

    var live: DynamicLive? {
        modules?.moduleDynamic?.major?.live
    }

    var paidContent: DynamicPaidContent? {
        modules?.moduleDynamic?.paidContent
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

    var containsDynamicAdPromotion: Bool {
        (BiliContentFilter.isDynamicAdCandidateType(type)
            && modules?.moduleDynamic?.containsDynamicAdPromotion == true)
            || original?.containsDynamicAdPromotion == true
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

    var contentDiagnosticSummary: String {
        let majorKeys = modules?.moduleDynamic?.major?.diagnosticKeys.joined(separator: ",") ?? "-"
        let additional = modules?.moduleDynamic?.additional
        let additionalKeys = additional?.diagnosticKeys.joined(separator: ",") ?? "-"
        return "id=\(idStr) type=\(type ?? "-") major=[\(majorKeys)] additionalType=\(additional?.type ?? "-") additional=[\(additionalKeys)] originalType=\(original?.type ?? "-")"
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

nonisolated struct DynamicBasic: Decodable, Hashable {
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

nonisolated struct DynamicOriginalItem: Identifiable, Decodable, Hashable {
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
        modules?.moduleDynamic?.major?.resolvedArchive
    }

    var live: DynamicLive? {
        modules?.moduleDynamic?.major?.live
    }

    var paidContent: DynamicPaidContent? {
        modules?.moduleDynamic?.paidContent
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
            || paidContent != nil
            || !imageItems.isEmpty
    }

    var containsGoodsPromotion: Bool {
        modules?.moduleDynamic?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        BiliContentFilter.isDynamicAdCandidateType(type)
            && modules?.moduleDynamic?.containsDynamicAdPromotion == true
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

nonisolated extension DynamicFeedItem {
    func matchesBlockedDynamicKeywords(_ keywords: [String]) -> Bool {
        let normalizedKeywords = keywords.compactMap(Self.normalizedBlockedDynamicKeyword)
        guard !normalizedKeywords.isEmpty else { return false }

        let searchText = keywordFilterTextSources.joined(separator: "\n")
        guard !searchText.isEmpty else { return false }
        return normalizedKeywords.contains { keyword in
            searchText.range(
                of: keyword,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) != nil
        }
    }

    fileprivate var keywordFilterTextSources: [String] {
        compactNonBlankDynamicFilterTexts([
            displayText,
            DynamicTextSegment.displayText(from: textSegments),
            archive?.title,
            archive?.desc,
            live?.displayTitle,
            paidContent?.title,
            paidContent?.subtitle
        ]) + (original?.keywordFilterTextSources ?? [])
    }

    private static func normalizedBlockedDynamicKeyword(_ keyword: String) -> String? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated extension DynamicOriginalItem {
    fileprivate var keywordFilterTextSources: [String] {
        compactNonBlankDynamicFilterTexts([
            displayText,
            DynamicTextSegment.displayText(from: textSegments),
            archive?.title,
            archive?.desc,
            live?.displayTitle,
            paidContent?.title,
            paidContent?.subtitle
        ])
    }
}

nonisolated private func compactNonBlankDynamicFilterTexts(_ values: [String?]) -> [String] {
    values.compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated struct DynamicModules: Decodable, Hashable {
    let moduleAuthor: DynamicAuthor?
    let moduleDynamic: DynamicModuleDynamic?
    let moduleStat: DynamicModuleStat?

    enum CodingKeys: String, CodingKey {
        case moduleAuthor = "module_author"
        case moduleDynamic = "module_dynamic"
        case moduleStat = "module_stat"
    }
}

nonisolated struct DynamicAuthor: Decodable, Hashable {
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

nonisolated struct DynamicModuleDynamic: Decodable, Hashable {
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

    var paidContent: DynamicPaidContent? {
        major?.paidContent ?? additional?.paidContent
    }

    var containsGoodsPromotion: Bool {
        additional?.containsGoodsPromotion == true
            || desc?.containsGoodsPromotion == true
            || major?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        desc?.containsDynamicAdPromotion == true
            || major?.containsDynamicAdPromotion == true
    }
}

nonisolated struct DynamicText: Decodable, Hashable {
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

    var containsDynamicAdPromotion: Bool {
        BiliContentFilter.isDynamicAdText(displayText)
    }
}

nonisolated struct DynamicAdditional: Decodable, Hashable {
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

    var paidContent: DynamicPaidContent? {
        DynamicPaidContent(raw: raw, sourceKey: type, preferredKind: nil)
    }

    var diagnosticKeys: [String] {
        raw.objectValueForDynamicParsing?.keys.sorted() ?? []
    }
}

nonisolated struct DynamicRichTextNode: Decodable, Hashable {
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

nonisolated struct DynamicRichTextEmoji: Decodable, Hashable {
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

nonisolated struct DynamicMajor: Decodable, Hashable {
    let archive: DynamicArchive?
    let opus: DynamicOpus?
    let draw: DynamicDraw?
    let live: DynamicLive?
    let paidContent: DynamicPaidContent?
    private let fallbackArchive: DynamicArchive?
    let fallbackDisplayText: String?
    let fallbackSegments: [DynamicTextSegment]
    let fallbackImageItems: [DynamicImageItem]
    let diagnosticKeys: [String]

    var resolvedArchive: DynamicArchive? {
        if let archive, archive.bvid?.isEmpty == false {
            return archive
        }
        return fallbackArchive ?? archive
    }

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

    var containsDynamicAdPromotion: Bool {
        draw?.containsDynamicAdPromotion == true
            || opus?.containsDynamicAdPromotion == true
            || BiliContentFilter.isDynamicAdText(fallbackDisplayText)
            || BiliContentFilter.isDynamicAdText(DynamicTextSegment.displayText(from: fallbackSegments))
    }

    enum CodingKeys: String, CodingKey {
        case archive, opus, draw, live
        case liveRcmd = "live_rcmd"
        case common
    }

    init(from decoder: Decoder) throws {
        let raw = try DynamicJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archive = try? container.decodeIfPresent(DynamicArchive.self, forKey: .archive)
        opus = try? container.decodeIfPresent(DynamicOpus.self, forKey: .opus)
        draw = try? container.decodeIfPresent(DynamicDraw.self, forKey: .draw)
        live = (try? container.decodeIfPresent(DynamicLive.self, forKey: .live))
            ?? (try? container.decodeIfPresent(DynamicLive.self, forKey: .liveRcmd))
            ?? (try? container.decodeIfPresent(DynamicLive.self, forKey: .common))
            ?? raw.dynamicMajorFallbackLive
        paidContent = DynamicPaidContent(raw: raw, sourceKey: nil, preferredKind: nil)
        fallbackArchive = raw.dynamicMajorFallbackArchive
        fallbackDisplayText = raw.dynamicMajorFallbackDisplayText
        fallbackSegments = raw.dynamicMajorFallbackTextSegments
        fallbackImageItems = raw.dynamicMajorFallbackImageItems
        diagnosticKeys = raw.objectValueForDynamicParsing?.keys.sorted() ?? []
    }
}

nonisolated struct DynamicPaidContent: Hashable {
    enum Kind: String, Hashable {
        case video
        case article
        case course
        case collection
        case unknown
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let cover: String?
    let jumpURL: String?
    let bvid: String?
    let aid: Int?
    let cvid: Int?
    let badgeText: String
    let isChargeExclusive: Bool
    let isLocked: Bool

    init?(
        raw: DynamicJSONValue,
        sourceKey: String?,
        preferredKind: Kind?
    ) {
        guard case .object(let rootObject) = raw else { return nil }

        let rootType = rootObject["type"]?.textValueForDynamicParsing
        let candidates = Self.candidateObjects(from: rootObject, sourceKey: sourceKey)
        for candidate in candidates {
            if let content = Self.content(
                from: candidate.object,
                sourceKey: candidate.key,
                rootType: rootType,
                preferredKind: preferredKind
            ) {
                self = content
                return
            }
        }
        return nil
    }

    private init(
        kind: Kind,
        title: String,
        subtitle: String?,
        cover: String?,
        jumpURL: String?,
        bvid: String?,
        aid: Int?,
        cvid: Int?,
        badgeText: String,
        isChargeExclusive: Bool,
        isLocked: Bool
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.cover = cover
        self.jumpURL = jumpURL
        self.bvid = bvid
        self.aid = aid
        self.cvid = cvid
        self.badgeText = badgeText
        self.isChargeExclusive = isChargeExclusive
        self.isLocked = isLocked
    }

    var normalizedCoverURL: String? {
        cover?.normalizedBiliURL()
    }

    var normalizedJumpURL: URL? {
        if let jumpURL, let url = URL(string: jumpURL.normalizedBiliURL()) {
            return url
        }
        if let bvid, !bvid.isEmpty {
            return URL(string: "https://www.bilibili.com/video/\(bvid)")
        }
        if let cvid, cvid > 0 {
            return URL(string: "https://www.bilibili.com/read/cv\(cvid)")
        }
        return nil
    }

    var isChargeArticleLike: Bool {
        guard isChargeExclusive else { return false }
        if kind == .article || cvid != nil {
            return true
        }
        let corpus = compactNonBlankDynamicFilterTexts([
            title,
            subtitle,
            badgeText
        ]).joined(separator: " ").lowercased()
        return corpus.contains("专栏") || corpus.contains("article")
    }

    func chargePageURL(author: DynamicAuthor?) -> URL? {
        if let mid = author?.mid, mid > 0 {
            return URL(string: "https://www.bilibili.com/h5/upower/index?mid=\(mid)")
        }
        guard let url = normalizedJumpURL,
              url.absoluteString.lowercased().contains("upower")
        else { return nil }
        return url
    }

    func asVideoItem(author: DynamicAuthor?) -> VideoItem? {
        guard kind == .video, let bvid, !bvid.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: normalizedCoverURL,
            desc: subtitle,
            duration: nil,
            pubdate: author?.pubTS,
            owner: author?.owner,
            stat: nil,
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    private static func candidateObjects(
        from root: [String: DynamicJSONValue],
        sourceKey: String?
    ) -> [(key: String, object: [String: DynamicJSONValue])] {
        var result = [(key: String, object: [String: DynamicJSONValue])]()
        var seenKeys = Set<String>()

        func append(_ key: String, value: DynamicJSONValue?) {
            guard let value else { return }
            switch value {
            case .object(let object):
                let signature = "\(key)#\(object.keys.sorted().joined(separator: ","))"
                guard seenKeys.insert(signature).inserted else { return }
                result.append((key, object))
                for nestedKey in ["content", "card", "item", "resource", "source", "sketch", "desc", "badge", "button", "cover_info"] {
                    if let nested = object[nestedKey]?.objectValueForDynamicParsing {
                        append("\(key).\(nestedKey)", value: .object(nested))
                    }
                }
            case .array(let values):
                for (index, item) in values.enumerated() {
                    append("\(key).\(index)", value: item)
                }
            case .string(let text):
                if let data = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(DynamicJSONValue.self, from: data) {
                    append(key, value: decoded)
                }
            case .number, .bool, .null:
                return
            }
        }

        if let sourceKey {
            append(sourceKey, value: .object(root))
        }

        let preferredKeys = [
            "upower_common", "upower_lottery", "charge", "paid", "blocked",
            "common", "article", "courses", "course", "pgc", "ugc_season",
            "medialist", "subscription", "subscription_new", "archive", "video"
        ]
        for key in preferredKeys {
            append(key, value: root[key])
        }
        append("root", value: .object(root))
        return result
    }

    private static func content(
        from object: [String: DynamicJSONValue],
        sourceKey: String,
        rootType: String?,
        preferredKind: Kind?
    ) -> DynamicPaidContent? {
        let objectType = object["type"]?.textValueForDynamicParsing
        let objectSubtype = object["sub_type"]?.textValueForDynamicParsing
        // Only trust structural API fields for paid-content identity. User-authored
        // titles/descriptions can naturally mention "充电" without being upower-only.
        let chargeSignalCorpus = compactNonBlankDynamicFilterTexts([
            sourceKey,
            rootType,
            objectType,
            objectSubtype,
            object["badge_text"]?.dynamicDisplayText,
            object["type_name"]?.dynamicDisplayText,
            object["hint_message"]?.dynamicDisplayText,
            nestedText(object, path: ["badge", "text"]),
            nestedText(object, path: ["badge", "title"]),
            nestedText(object, path: ["button", "text"])
        ])
        let lowerSource = "\(sourceKey) \(rootType ?? "") \(objectType ?? "") \(objectSubtype ?? "")".lowercased()
        let isChargeExclusive = hasTruthyChargeFlag(in: object)
            || chargeSignalCorpus.contains { isChargeMarker($0) }
        let kind = preferredKind ?? inferredKind(source: lowerSource, object: object)

        if sourceKey.contains("archive") || sourceKey.contains("video") {
            guard isChargeExclusive else { return nil }
        }

        let jumpURLText = normalizedJumpURLString(firstNonBlankDynamicText([
            object["jump_url"]?.textValueForDynamicParsing,
            object["jumpUrl"]?.textValueForDynamicParsing,
            object["url"]?.textValueForDynamicParsing,
            object["uri"]?.textValueForDynamicParsing,
            object["link"]?.textValueForDynamicParsing,
            object["web_url"]?.textValueForDynamicParsing,
            object["schema"]?.textValueForDynamicParsing
        ]))
        let bvid = firstNonBlankDynamicText([
            object["bvid"]?.textValueForDynamicParsing,
            object["bvid_str"]?.textValueForDynamicParsing,
            bvid(from: jumpURLText)
        ])
        let cvid = firstNonNilInt([
            object["cvid"]?.intValueForDynamicParsing,
            object["cv_id"]?.intValueForDynamicParsing,
            cvid(from: jumpURLText),
            kind == .article ? object["id"]?.intValueForDynamicParsing : nil,
            kind == .article ? object["rid"]?.intValueForDynamicParsing : nil
        ])
        let resolvedKind: Kind = {
            if kind == .unknown, bvid != nil { return .video }
            if kind == .unknown, cvid != nil { return .article }
            return kind
        }()
        guard isChargeExclusive else { return nil }

        let title = firstNonBlankDynamicText([
            object["title"]?.dynamicDisplayText,
            object["name"]?.dynamicDisplayText,
            object["long_title"]?.dynamicDisplayText,
            object["headline"]?.dynamicDisplayText,
            object["desc"]?.dynamicDisplayText,
            object["summary"]?.dynamicDisplayText,
            object["content"]?.dynamicDisplayText,
            object["message"]?.dynamicDisplayText,
            object["hint_message"]?.dynamicDisplayText
        ]) ?? defaultTitle(kind: resolvedKind, isChargeExclusive: isChargeExclusive)
        let subtitle = firstNonBlankDynamicText([
            object["sub_title"]?.dynamicDisplayText,
            object["subtitle"]?.dynamicDisplayText,
            object["desc"]?.dynamicDisplayText == title ? nil : object["desc"]?.dynamicDisplayText,
            object["summary"]?.dynamicDisplayText == title ? nil : object["summary"]?.dynamicDisplayText,
            object["hint_message"]?.dynamicDisplayText == title ? nil : object["hint_message"]?.dynamicDisplayText
        ])
        let cover = firstImageURL(from: object)
        let badge = badgeText(
            object: object,
            kind: resolvedKind,
            isChargeExclusive: isChargeExclusive
        )
        let isLocked = lowerSource.contains("blocked")
            || chargeSignalCorpus.contains { text in
                let normalized = text.lowercased()
                return normalized.contains("不可见")
                    || normalized.contains("暂不可见")
                    || normalized.contains("需充电")
                    || normalized.contains("解锁")
                    || normalized.contains("locked")
            }

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return DynamicPaidContent(
            kind: resolvedKind,
            title: title,
            subtitle: subtitle,
            cover: cover,
            jumpURL: jumpURLText,
            bvid: bvid,
            aid: firstNonNilInt([
                object["aid"]?.intValueForDynamicParsing,
                object["id"]?.intValueForDynamicParsing,
                object["rid"]?.intValueForDynamicParsing
            ]),
            cvid: cvid,
            badgeText: badge,
            isChargeExclusive: isChargeExclusive,
            isLocked: isLocked
        )
    }

    private static func inferredKind(
        source: String,
        object: [String: DynamicJSONValue]
    ) -> Kind {
        if source.contains("article") || source.contains("read") || cvid(from: source) != nil {
            return .article
        }
        if source.contains("course") || source.contains("courses") {
            return .course
        }
        if source.contains("pgc")
            || source.contains("season")
            || source.contains("medialist")
            || source.contains("subscription") {
            return .collection
        }
        if source.contains("archive")
            || source.contains("video")
            || source.contains("ugc")
            || object["bvid"] != nil
            || object["bvid_str"] != nil {
            return .video
        }
        if object["cvid"] != nil || object["cv_id"] != nil {
            return .article
        }
        return .unknown
    }

    private static func firstNonNilInt(_ values: [Int?]) -> Int? {
        values.compactMap { $0 }.first
    }

    private static func hasTruthyChargeFlag(in object: [String: DynamicJSONValue]) -> Bool {
        let flagKeys = [
            "is_upower_exclusive", "is_upower_play", "is_charge", "is_charged",
            "need_charge", "need_pay", "is_paid", "pay_only", "locked"
        ]
        return flagKeys.contains { key in
            switch object[key] {
            case .bool(let value):
                return value
            case .number(let value):
                return value != "0"
            case .string(let value):
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized == "1" || normalized == "true" || normalized == "yes"
            case .object, .array, .null, .none:
                return false
            }
        }
    }

    private static func isChargeMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("upower")
            || normalized.contains("charge")
            || normalized.contains("paid")
            || normalized.contains("exclusive")
            || normalized.contains("充电")
            || normalized.contains("付费")
            || normalized.contains("专属")
    }

    private static func firstImageURL(from object: [String: DynamicJSONValue]) -> String? {
        let directKeys = [
            "cover", "cover_url", "pic", "image", "image_url", "img_src",
            "thumbnail", "thumb", "bg_img", "background", "poster"
        ]
        for key in directKeys {
            if let url = imageURL(from: object[key]) {
                return url
            }
        }
        for key in ["covers", "pics", "images", "items"] {
            if let image = object[key]?.dynamicImageItems.first?.normalizedURL {
                return image
            }
        }
        for key in ["cover_info", "image", "pic", "content", "card", "item", "resource"] {
            if let nested = object[key]?.objectValueForDynamicParsing,
               let url = firstImageURL(from: nested) {
                return url
            }
        }
        return nil
    }

    private static func imageURL(from value: DynamicJSONValue?) -> String? {
        guard let value else { return nil }
        if let text = value.textValueForDynamicParsing {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL()
            guard normalized.hasPrefix("http://") || normalized.hasPrefix("https://") else { return nil }
            return normalized
        }
        if let object = value.objectValueForDynamicParsing {
            return firstImageURL(from: object)
        }
        return nil
    }

    private static func badgeText(
        object: [String: DynamicJSONValue],
        kind: Kind,
        isChargeExclusive: Bool
    ) -> String {
        let candidate = firstNonBlankDynamicText([
            object["badge_text"]?.dynamicDisplayText,
            object["type_name"]?.dynamicDisplayText,
            object["label"]?.dynamicDisplayText,
            object["tag"]?.dynamicDisplayText,
            nestedText(object, path: ["badge", "text"]),
            nestedText(object, path: ["badge", "title"]),
            nestedText(object, path: ["button", "text"])
        ])
        if let candidate, isChargeMarker(candidate) {
            return candidate
        }
        if isChargeExclusive {
            switch kind {
            case .video:
                return "充电视频"
            case .article:
                return "充电专栏"
            case .course:
                return "充电课程"
            case .collection, .unknown:
                return "充电专属"
            }
        }
        if let candidate, !candidate.isEmpty {
            return candidate
        }
        switch kind {
        case .video:
            return "视频"
        case .article:
            return "专栏"
        case .course:
            return "课程"
        case .collection:
            return "合集"
        case .unknown:
            return "动态内容"
        }
    }

    private static func defaultTitle(kind: Kind, isChargeExclusive: Bool) -> String {
        if isChargeExclusive {
            switch kind {
            case .video:
                return "充电视频"
            case .article:
                return "充电专栏"
            case .course:
                return "充电课程"
            case .collection, .unknown:
                return "充电专属内容"
            }
        }
        switch kind {
        case .video:
            return "视频"
        case .article:
            return "专栏"
        case .course:
            return "课程"
        case .collection:
            return "合集"
        case .unknown:
            return "动态内容"
        }
    }

    private static func nestedText(
        _ object: [String: DynamicJSONValue],
        path: [String]
    ) -> String? {
        guard let first = path.first else { return nil }
        var value = object[first]
        for key in path.dropFirst() {
            value = value?.objectValueForDynamicParsing?[key]
        }
        return value?.dynamicDisplayText
    }

    private static func normalizedJumpURLString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let bvid = bvid(from: trimmed) {
            return "https://www.bilibili.com/video/\(bvid)"
        }
        if let cvid = cvid(from: trimmed) {
            return "https://www.bilibili.com/read/cv\(cvid)"
        }
        let normalized = trimmed.normalizedBiliURL()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return normalized
        }
        return nil
    }

    private static func bvid(from text: String?) -> String? {
        guard let text,
              let range = text.range(of: #"BV[A-Za-z0-9]{10,}"#, options: .regularExpression)
        else { return nil }
        return String(text[range])
    }

    private static func cvid(from text: String?) -> Int? {
        guard let text else { return nil }
        let patterns = [
            #"cv(\d+)"#,
            #"read/(?:mobile/)?(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: text),
                  let value = Int(text[range])
            else { continue }
            return value
        }
        return nil
    }
}

nonisolated struct DynamicLive: Decodable, Hashable {
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
        let rawObject = raw.objectValueForDynamicParsing ?? [:]
        let embeddedObject = Self.embeddedContentObject(from: rawObject) ?? [:]
        let object = rawObject.merging(embeddedObject) { current, _ in current }
        let playInfo = embeddedObject["live_play_info"]?.objectValueForDynamicParsing
            ?? rawObject["live_play_info"]?.objectValueForDynamicParsing
            ?? object["live_play_info"]?.objectValueForDynamicParsing
        let source = playInfo ?? object
        let watchedShow = source["watched_show"]?.objectValueForDynamicParsing
        let pendants = source["pendants"]?.objectValueForDynamicParsing ?? object["pendants"]?.objectValueForDynamicParsing

        title = firstNonBlankDynamicText([
            source["title"]?.textValueForDynamicParsing,
            object["title"]?.textValueForDynamicParsing,
            object["desc"]?.textValueForDynamicParsing
        ])
        cover = Self.firstImageURL(from: [source, object, embeddedObject, rawObject])
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

    private static func embeddedContentObject(from object: [String: DynamicJSONValue]) -> [String: DynamicJSONValue]? {
        for key in ["content", "card", "live_play_info"] {
            guard let value = object[key] else { continue }
            if let nested = value.objectValueForDynamicParsing {
                return nested
            }
            guard let text = value.textValueForDynamicParsing,
                  let data = text.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(DynamicJSONValue.self, from: data)
            else { continue }
            if let nested = decoded.objectValueForDynamicParsing {
                return nested
            }
        }
        return nil
    }

    private static func firstImageURL(from objects: [[String: DynamicJSONValue]]) -> String? {
        let keys = [
            "cover", "cover_url", "keyframe", "live_cover", "room_cover",
            "user_cover", "system_cover", "pic", "image", "image_url",
            "img_src", "thumbnail", "thumb"
        ]
        for object in objects {
            for key in keys {
                if let url = imageURL(from: object[key]) {
                    return url
                }
            }
        }
        for object in objects {
            for key in ["cover_info", "image", "pic", "room_info", "live_play_info"] {
                if let nested = object[key]?.objectValueForDynamicParsing,
                   let url = firstImageURL(from: [nested]) {
                    return url
                }
            }
        }
        return nil
    }

    private static func imageURL(from value: DynamicJSONValue?) -> String? {
        guard let value else { return nil }
        if let text = value.textValueForDynamicParsing,
           let url = normalizedImageURL(text) {
            return url
        }
        if let object = value.objectValueForDynamicParsing {
            return firstImageURL(from: [object])
        }
        return nil
    }

    private static func normalizedImageURL(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL()
        guard normalized.hasPrefix("https://") || normalized.hasPrefix("http://"),
              let url = URL(string: normalized)
        else { return nil }
        let pathExtension = url.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif"]
        guard normalized.contains("hdslb.com")
            || normalized.contains("biliimg.com")
            || imageExtensions.contains(pathExtension)
        else { return nil }
        return normalized
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

    var hasLiveIdentity: Bool {
        roomID != nil
            || uid != nil
            || normalizedLinkURL != nil
            || normalizedCoverURL != nil
            || title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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

nonisolated struct DynamicOpus: Decodable, Hashable {
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

    var containsDynamicAdPromotion: Bool {
        summary?.containsDynamicAdPromotion == true
            || content?.containsDynamicAdPromotion == true
            || desc?.containsDynamicAdPromotion == true
            || BiliContentFilter.isDynamicAdText(title)
    }
}

nonisolated struct DynamicDraw: Decodable, Hashable {
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

    var containsDynamicAdPromotion: Bool {
        summary?.containsDynamicAdPromotion == true
            || desc?.containsDynamicAdPromotion == true
            || BiliContentFilter.isDynamicAdText(title)
    }
}

nonisolated struct DynamicImageItem: Decodable, Hashable {
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
        case originalWidth = "orig_width"
        case originalHeight = "orig_height"
        case widthShort = "w"
        case heightShort = "h"
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
            ?? container.decodeLossyIntIfPresent(forKey: .originalWidth)
            ?? container.decodeLossyIntIfPresent(forKey: .widthShort)
        height = container.decodeLossyIntIfPresent(forKey: .height)
            ?? container.decodeLossyIntIfPresent(forKey: .imgHeight)
            ?? container.decodeLossyIntIfPresent(forKey: .imageHeight)
            ?? container.decodeLossyIntIfPresent(forKey: .originalHeight)
            ?? container.decodeLossyIntIfPresent(forKey: .heightShort)
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
        if let width, let height, width > 0, height > 0 {
            return Double(width) / Double(height)
        }
        if let ratio = normalizedURL?.biliImageURLAspectRatio {
            return ratio
        }
        return 1
    }
}

nonisolated struct DynamicModuleStat: Decodable, Hashable {
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

nonisolated struct DynamicStatItem: Decodable, Hashable {
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

nonisolated struct DynamicArchive: Decodable, Hashable {
    let aid: Int?
    let bvid: String?
    let title: String?
    let cover: String?
    let desc: String?
    let durationText: String?
    let duration: Int?
    let stat: DynamicArchiveStat?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, cover, desc, stat, duration, length
        case durationText = "duration_text"
        case durationTextAlt = "durationText"
        case durationStr = "duration_str"
        case durationString = "duration_string"
        case durationSecond = "duration_second"
        case durationSeconds = "duration_seconds"
        case durationTime = "duration_time"
        case durationMS = "duration_ms"
        case durationMillis = "duration_millis"
        case coverRightText = "cover_right_text"
        case coverRightTextAlt = "coverRightText"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
        durationText = firstNonBlankDynamicText([
            container.decodeLossyStringIfPresent(forKey: .durationText),
            container.decodeLossyStringIfPresent(forKey: .durationTextAlt),
            container.decodeLossyStringIfPresent(forKey: .durationStr),
            container.decodeLossyStringIfPresent(forKey: .durationString),
            container.decodeLossyStringIfPresent(forKey: .length),
            container.decodeLossyStringIfPresent(forKey: .coverRightText),
            container.decodeLossyStringIfPresent(forKey: .coverRightTextAlt),
            container.decodeLossyStringIfPresent(forKey: .duration)
        ])
        duration = Self.durationSeconds(
            text: durationText,
            seconds: container.decodeLossyIntIfPresent(forKey: .duration)
                ?? container.decodeLossyIntIfPresent(forKey: .durationSecond)
                ?? container.decodeLossyIntIfPresent(forKey: .durationSeconds)
                ?? container.decodeLossyIntIfPresent(forKey: .durationTime),
            milliseconds: container.decodeLossyIntIfPresent(forKey: .durationMS)
                ?? container.decodeLossyIntIfPresent(forKey: .durationMillis)
        )
        stat = try container.decodeIfPresent(DynamicArchiveStat.self, forKey: .stat)
    }

    init?(fallbackObject object: [String: DynamicJSONValue]) {
        let jumpURL = firstNonBlankDynamicText([
            object["jump_url"]?.textValueForDynamicParsing,
            object["url"]?.textValueForDynamicParsing,
            object["uri"]?.textValueForDynamicParsing,
            object["link"]?.textValueForDynamicParsing,
            object["jumpUrl"]?.textValueForDynamicParsing
        ])
        let bvid = firstNonBlankDynamicText([
            object["bvid"]?.textValueForDynamicParsing,
            object["bvid_str"]?.textValueForDynamicParsing,
            Self.bvid(from: jumpURL)
        ])
        guard let bvid, !bvid.isEmpty else { return nil }

        let statObject = object["stat"]?.objectValueForDynamicParsing
            ?? object["cnt_info"]?.objectValueForDynamicParsing
        let durationText = firstNonBlankDynamicText([
            object["duration_text"]?.textValueForDynamicParsing,
            object["durationText"]?.textValueForDynamicParsing,
            object["duration_str"]?.textValueForDynamicParsing,
            object["duration_string"]?.textValueForDynamicParsing,
            object["length"]?.textValueForDynamicParsing,
            object["cover_right_text"]?.textValueForDynamicParsing,
            object["coverRightText"]?.textValueForDynamicParsing,
            object["duration"]?.textValueForDynamicParsing
        ])

        self.aid = object["aid"]?.intValueForDynamicParsing
            ?? object["id"]?.intValueForDynamicParsing
            ?? object["rid"]?.intValueForDynamicParsing
        self.bvid = bvid
        self.title = firstNonBlankDynamicText([
            object["title"]?.textValueForDynamicParsing,
            object["long_title"]?.textValueForDynamicParsing,
            object["name"]?.textValueForDynamicParsing,
            object["desc"]?.textValueForDynamicParsing
        ])
        self.cover = firstNonBlankDynamicText([
            object["cover"]?.textValueForDynamicParsing,
            object["cover_url"]?.textValueForDynamicParsing,
            object["pic"]?.textValueForDynamicParsing,
            object["image_url"]?.textValueForDynamicParsing,
            object["thumbnail"]?.textValueForDynamicParsing,
            object["thumb"]?.textValueForDynamicParsing
        ])?.normalizedBiliURL()
        self.desc = object["desc"]?.textValueForDynamicParsing
        self.durationText = durationText
        self.duration = Self.durationSeconds(
            text: durationText,
            seconds: object["duration"]?.intValueForDynamicParsing
                ?? object["duration_second"]?.intValueForDynamicParsing
                ?? object["duration_seconds"]?.intValueForDynamicParsing
                ?? object["duration_time"]?.intValueForDynamicParsing,
            milliseconds: object["duration_ms"]?.intValueForDynamicParsing
                ?? object["duration_millis"]?.intValueForDynamicParsing
        )
        self.stat = DynamicArchiveStat(fallbackObject: statObject)
    }

    func asVideoItem(author: DynamicAuthor?) -> VideoItem? {
        guard let bvid, !bvid.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: aid,
            title: title ?? "视频",
            pic: cover?.normalizedBiliURL(),
            desc: desc,
            duration: duration,
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

    nonisolated private static func durationSeconds(text: String?, seconds: Int?, milliseconds: Int?) -> Int? {
        if let parsed = text.flatMap(durationSeconds) {
            return parsed
        }
        if let normalized = normalizedSeconds(seconds) {
            return normalized
        }
        if let milliseconds, milliseconds > 0 {
            return max(milliseconds / 1000, 1)
        }
        return nil
    }

    nonisolated private static func durationSeconds(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "--:--" else { return nil }
        if let seconds = Int(trimmed), let normalized = normalizedSeconds(seconds) {
            return normalized
        }

        let normalizedText = trimmed
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: " ", with: "")
        let parts = normalizedText.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return positiveDuration(parts[0] * 60 + parts[1])
        }
        if parts.count == 3 {
            return positiveDuration(parts[0] * 3600 + parts[1] * 60 + parts[2])
        }
        return chineseDurationSeconds(normalizedText)
    }

    nonisolated private static func normalizedSeconds(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        if value > 100_000 {
            return max(value / 1000, 1)
        }
        return value
    }

    nonisolated private static func positiveDuration(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }

    nonisolated private static func chineseDurationSeconds(_ value: String) -> Int? {
        let pattern = #"(?:(\d+)(?:小时|时|h))?(?:(\d+)(?:分钟|分|m))?(?:(\d+)(?:秒|s))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.length > 0
        else { return nil }

        func component(_ index: Int) -> Int {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: value)
            else { return 0 }
            return Int(value[range]) ?? 0
        }

        return positiveDuration(component(1) * 3600 + component(2) * 60 + component(3))
    }

    nonisolated private static func bvid(from text: String?) -> String? {
        guard let text else { return nil }
        guard let range = text.range(of: #"BV[A-Za-z0-9]{10,}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

nonisolated struct DynamicArchiveStat: Decodable, Hashable {
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

    init?(fallbackObject object: [String: DynamicJSONValue]?) {
        guard let object else { return nil }
        play = object["play"]?.intValueForDynamicParsing
            ?? object["view"]?.intValueForDynamicParsing
            ?? object["view_count"]?.intValueForDynamicParsing
        reply = object["reply"]?.intValueForDynamicParsing
            ?? object["danmaku"]?.intValueForDynamicParsing
            ?? object["comment"]?.intValueForDynamicParsing
        like = object["like"]?.intValueForDynamicParsing
        coin = object["coin"]?.intValueForDynamicParsing
        favorite = object["favorite"]?.intValueForDynamicParsing
            ?? object["collect"]?.intValueForDynamicParsing
    }
}

nonisolated struct QRCodeLoginInfo: Decodable, Hashable {
    let url: String
    let qrcodeKey: String

    enum CodingKeys: String, CodingKey {
        case url
        case qrcodeKey = "qrcode_key"
    }
}

nonisolated struct QRCodeLoginPollData: Decodable, Hashable {
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

nonisolated struct LiveRecommendData: Decodable {
    let recommendRoomList: [LiveRoom]?

    enum CodingKeys: String, CodingKey {
        case recommendRoomList = "recommend_room_list"
    }
}

nonisolated struct LiveAreaGroup: Identifiable, Decodable, Hashable {
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

nonisolated struct LiveArea: Identifiable, Decodable, Hashable {
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

nonisolated struct LiveRoom: Identifiable, Decodable, Hashable {
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
        coverCandidates.first
    }

    var coverCandidates: [String] {
        var seen = Set<String>()
        var result = [String]()
        for candidate in [keyframe, cover] {
            let normalized = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .normalizedBiliURL() ?? ""
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    var isLive: Bool {
        liveStatus == nil || liveStatus == 1
    }

    var anchorOwner: VideoOwner {
        VideoOwner(mid: uid ?? 0, name: uname, face: face?.normalizedBiliURL())
    }
}

nonisolated struct LiveRoomInfo: Decodable, Hashable {
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

nonisolated struct LiveRoomSummary: Decodable, Hashable {
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

nonisolated struct LivePlayInfoData: Decodable {
    let playurlInfo: LivePlayURLInfo?

    enum CodingKeys: String, CodingKey {
        case playurlInfo = "playurl_info"
    }

    var firstPlayableURL: URL? {
        playableURLCandidates.first?.url
    }

    var playableURLCandidates: [LiveStreamURLCandidate] {
        playurlInfo?.playurl?.stream?
            .playableURLCandidates(preferHLS: true) ?? []
    }

    var availableQualities: [LiveStreamQuality] {
        let described = playurlInfo?.playurl?.qualityDescriptions ?? []
        let accepted = playurlInfo?.playurl?.stream?.acceptedQualities ?? []
        return LiveStreamQuality.merged(described + accepted)
    }
}

nonisolated struct LiveRoomPlayURLData: Decodable {
    let durl: [LiveRoomPlayURLItem]?

    var firstURL: URL? {
        playableURLCandidates.first?.url
    }

    var playableURLCandidates: [LiveStreamURLCandidate] {
        (durl ?? []).compactMap { item in
            URL(string: item.url.normalizedBiliURL()).map {
                LiveStreamURLCandidate(
                    url: $0,
                    protocolName: "legacy",
                    formatName: $0.liveStreamFormatHint,
                    codecName: nil,
                    currentQN: nil,
                    qualityTitle: nil,
                    source: "legacy"
                )
            }
        }
    }
}

nonisolated struct LiveRoomPlayURLItem: Decodable {
    let url: String
}

nonisolated struct LiveStreamURLCandidate: Equatable, Hashable {
    let url: URL
    let protocolName: String?
    let formatName: String?
    let codecName: String?
    let currentQN: Int?
    let qualityTitle: String?
    let source: String

    var isLikelyHLS: Bool {
        protocolName?.localizedCaseInsensitiveContains("hls") == true
            || formatName?.localizedCaseInsensitiveContains("fmp4") == true
            || formatName?.localizedCaseInsensitiveContains("ts") == true
            || url.isLikelyHLSManifest
    }
}

nonisolated struct LiveStreamFetchResult: Equatable, Hashable {
    let candidates: [LiveStreamURLCandidate]
    let qualities: [LiveStreamQuality]

    var playableQualities: [LiveStreamQuality] {
        let derived = LiveStreamQuality.merged(
            candidates.compactMap { candidate in
                guard let qn = candidate.currentQN, qn > 0 else { return nil }
                return LiveStreamQuality(qn: qn, description: candidate.qualityTitle)
            }
        )
        return LiveStreamQuality.merged(qualities + derived)
    }
}

nonisolated struct LiveStreamQuality: Identifiable, Decodable, Equatable, Hashable {
    let qn: Int
    let description: String?

    var id: Int { qn }

    enum CodingKeys: String, CodingKey {
        case qn
        case description = "desc"
        case descriptionAlt = "description"
    }

    init(qn: Int, description: String?) {
        self.qn = qn
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        qn = container.decodeLossyIntIfPresent(forKey: .qn) ?? 0
        description = container.decodeLossyStringIfPresent(forKey: .description)
            ?? container.decodeLossyStringIfPresent(forKey: .descriptionAlt)
    }

    var title: String {
        if let description, !description.isEmpty {
            return description
        }
        return Self.defaultTitle(for: qn)
    }

    static func defaultTitle(for qn: Int) -> String {
        switch qn {
        case 10000:
            return "原画"
        case 400:
            return "蓝光"
        case 250:
            return "超清"
        case 150:
            return "高清"
        case 80:
            return "流畅"
        default:
            return "清晰度 \(qn)"
        }
    }

    static func merged(_ values: [LiveStreamQuality]) -> [LiveStreamQuality] {
        var seen = Set<Int>()
        return values
            .filter { $0.qn > 0 }
            .sorted { $0.qn > $1.qn }
            .filter { seen.insert($0.qn).inserted }
    }
}

nonisolated struct LiveAnchorInfoData: Decodable, Hashable {
    let info: LiveAnchorProfile?
    let relationInfo: LiveAnchorRelationInfo?

    enum CodingKeys: String, CodingKey {
        case info
        case relationInfo = "relation_info"
    }
}

nonisolated struct LiveAnchorProfile: Decodable, Hashable {
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

nonisolated struct LiveAnchorRelationInfo: Decodable, Hashable {
    let attention: Int?

    enum CodingKeys: String, CodingKey {
        case attention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attention = container.decodeLossyIntIfPresent(forKey: .attention)
    }
}

nonisolated struct FollowedLiveRoomsData: Decodable {
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

nonisolated struct LiveDanmakuConnectionInfoData: Decodable, Sendable {
    let token: String?
    let hostList: [LiveDanmakuHost]

    enum CodingKeys: String, CodingKey {
        case token
        case hostList = "host_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = container.decodeLossyStringIfPresent(forKey: .token)
        hostList = try container.decodeIfPresent([LiveDanmakuHost].self, forKey: .hostList) ?? []
    }
}

nonisolated struct LiveDanmakuHost: Decodable, Hashable, Sendable {
    let host: String
    let port: Int?
    let wssPort: Int?
    let wsPort: Int?

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case wssPort = "wss_port"
        case wsPort = "ws_port"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = container.decodeLossyStringIfPresent(forKey: .host) ?? ""
        port = container.decodeLossyIntIfPresent(forKey: .port)
        wssPort = container.decodeLossyIntIfPresent(forKey: .wssPort)
        wsPort = container.decodeLossyIntIfPresent(forKey: .wsPort)
    }

    var webSocketURL: URL? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        let portValue = wssPort ?? port ?? wsPort ?? 443
        return URL(string: "wss://\(trimmedHost):\(portValue)/sub")
    }
}

nonisolated struct LivePlayURLInfo: Decodable {
    let playurl: LivePlayURL?
}

nonisolated struct LivePlayURL: Decodable {
    let stream: [LiveStream]?
    let qualityDescriptions: [LiveStreamQuality]?

    enum CodingKeys: String, CodingKey {
        case stream
        case qualityDescriptions = "g_qn_desc"
    }
}

nonisolated struct LiveStream: Decodable {
    let protocolName: String?
    let format: [LiveStreamFormat]?

    enum CodingKeys: String, CodingKey {
        case format
        case protocolName = "protocol_name"
    }
}

nonisolated private extension Array where Element == LiveStream {
    var acceptedQualities: [LiveStreamQuality] {
        let values = flatMap { stream in
            (stream.format ?? []).flatMap { format in
                (format.codec ?? []).flatMap { codec in
                    codec.acceptedQualities
                }
            }
        }
        return LiveStreamQuality.merged(values)
    }
}

nonisolated struct LiveStreamFormat: Decodable {
    let formatName: String?
    let codec: [LiveStreamCodec]?

    enum CodingKeys: String, CodingKey {
        case codec
        case formatName = "format_name"
    }
}

nonisolated struct LiveStreamCodec: Decodable {
    let codecName: String?
    let currentQN: Int?
    let acceptQN: [Int]?
    let baseURL: String
    let urlInfo: [LiveStreamURLInfo]?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case currentQN = "current_qn"
        case acceptQN = "accept_qn"
        case baseURL = "base_url"
        case urlInfo = "url_info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codecName = try container.decodeIfPresent(String.self, forKey: .codecName)
        currentQN = container.decodeLossyIntIfPresent(forKey: .currentQN)
        acceptQN = try container.decodeIfPresent([Int].self, forKey: .acceptQN)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        urlInfo = try container.decodeIfPresent([LiveStreamURLInfo].self, forKey: .urlInfo)
    }

    var acceptedQualities: [LiveStreamQuality] {
        LiveStreamQuality.merged(
            (acceptQN ?? []).map { LiveStreamQuality(qn: $0, description: nil) }
                + [currentQN].compactMap { qn in
                    guard let qn else { return nil }
                    return LiveStreamQuality(qn: qn, description: nil)
                }
        )
    }

    var playableURLs: [URL] {
        if let urlInfo, !urlInfo.isEmpty {
            return urlInfo.compactMap { info in
                Self.makeURL(host: info.host, baseURL: baseURL, extra: info.extra)
            }
        }
        return Self.makeURL(host: "", baseURL: baseURL, extra: nil).map { [$0] } ?? []
    }

    func playableURLCandidates(protocolName: String?, formatName: String?, source: String) -> [LiveStreamURLCandidate] {
        playableURLs.map {
            LiveStreamURLCandidate(
                url: $0,
                protocolName: protocolName,
                formatName: formatName,
                codecName: codecName,
                currentQN: currentQN,
                qualityTitle: currentQN.map(LiveStreamQuality.defaultTitle),
                source: source
            )
        }
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

nonisolated struct LiveStreamURLInfo: Decodable {
    let host: String
    let extra: String?
}

nonisolated struct NavUserInfo: Decodable {
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

nonisolated struct WBIImage: Decodable {
    let imgURL: String
    let subURL: String

    enum CodingKeys: String, CodingKey {
        case imgURL = "img_url"
        case subURL = "sub_url"
    }
}

nonisolated private extension Array where Element == LiveStream {
    func firstPlayableURL(preferHLS: Bool) -> URL? {
        playableURLCandidates(preferHLS: preferHLS).first?.url
    }

    func playableURLCandidates(preferHLS: Bool) -> [LiveStreamURLCandidate] {
        let candidates = flatMap { stream in
            (stream.format ?? []).flatMap { format in
                (format.codec ?? []).flatMap { codec in
                    codec.playableURLCandidates(
                        protocolName: stream.protocolName,
                        formatName: format.formatName,
                        source: "v2"
                    )
                }
            }
        }

        return candidates
            .filter { candidate in
                guard candidate.url.scheme == "https" || candidate.url.scheme == "http" else { return false }
                if preferHLS {
                    return candidate.isLikelyHLS || candidate.url.isLikelyAVPlayerFile
                }
                return true
            }
            .sorted { lhs, rhs in
                lhs.livePlaybackPriorityScore < rhs.livePlaybackPriorityScore
            }
            .removingDuplicateLiveURLs()
    }
}

nonisolated private extension String {
    func trimmingPrefixCharacters(_ characters: Set<Character>) -> String {
        var result = self
        while let first = result.first, characters.contains(first) {
            result.removeFirst()
        }
        return result
    }
}

nonisolated private extension LiveStreamURLCandidate {
    var livePlaybackPriorityScore: Int {
        var score = 0
        if !isLikelyHLS {
            score += 10_000
        }
        if formatName?.localizedCaseInsensitiveContains("fmp4") == true {
            score -= 600
        }
        if url.isLikelyHLSManifest {
            score -= 500
        }
        if protocolName?.localizedCaseInsensitiveContains("hls") == true {
            score -= 300
        }
        if formatName?.localizedCaseInsensitiveContains("ts") == true {
            score += 180
        }

        let codec = codecName?.lowercased() ?? ""
        if codec.contains("avc") || codec.contains("h264") {
            score -= 240
        } else if codec.contains("hevc") || codec.contains("h265") {
            score += 260
        } else if codec.contains("av1") {
            score += 420
        }

        if let currentQN {
            score += max(0, currentQN - 400) / 100
        }
        return score
    }
}

nonisolated private extension Array where Element == LiveStreamURLCandidate {
    func removingDuplicateLiveURLs() -> [LiveStreamURLCandidate] {
        var seen = Set<String>()
        var result: [LiveStreamURLCandidate] = []
        for candidate in self {
            guard seen.insert(candidate.url.absoluteString).inserted else { continue }
            result.append(candidate)
        }
        return result
    }
}

nonisolated private extension URL {
    var isLikelyHLSManifest: Bool {
        pathExtension.localizedCaseInsensitiveCompare("m3u8") == .orderedSame
            || absoluteString.range(of: ".m3u8", options: .caseInsensitive) != nil
    }

    var isLikelyAVPlayerFile: Bool {
        let ext = pathExtension.lowercased()
        return ext == "mp4" || ext == "m4v" || ext == "mov"
    }

    var liveStreamFormatHint: String? {
        if isLikelyHLSManifest {
            return "hls"
        }
        let ext = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? nil : ext
    }
}

nonisolated extension String {
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

    func biliCoverThumbnailURL(
        fitting size: CGSize,
        scale: CGFloat,
        maximumPixelLength: Int = 1280
    ) -> String {
        biliCoverThumbnailURL(
            width: Self.biliThumbnailPixelLength(size.width, scale: scale, maximum: maximumPixelLength),
            height: Self.biliThumbnailPixelLength(size.height, scale: scale, maximum: maximumPixelLength)
        )
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

    func biliImageThumbnailURL(
        fitting size: CGSize,
        scale: CGFloat,
        maximumPixelLength: Int = 1280
    ) -> String {
        biliImageThumbnailURL(
            maxSide: Self.biliThumbnailMaxPixelSide(
                fitting: size,
                scale: scale,
                maximumPixelLength: maximumPixelLength
            )
        )
    }

    func biliImageCacheIdentityURLString() -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        let base = normalized.biliImageBaseURL()
        guard normalized.contains("imageView2") else {
            return base
        }

        if let ratio = normalized.biliImageURLAspectRatio {
            let ratioBucket = Int((ratio * 100).rounded())
            return "\(base)#crop-\(ratioBucket)"
        }
        return "\(base)#fit"
    }

    static func biliThumbnailMaxPixelSide(
        fitting size: CGSize,
        scale: CGFloat,
        maximumPixelLength: Int = 1280
    ) -> Int {
        Swift.max(
            biliThumbnailPixelLength(size.width, scale: scale, maximum: maximumPixelLength),
            biliThumbnailPixelLength(size.height, scale: scale, maximum: maximumPixelLength)
        )
    }

    var biliImageURLAspectRatio: Double? {
        let normalized = normalizedBiliURL()
        let candidates = [
            #"(?i)[@_/?&](?:w|width)[_=/:-]?(\d{2,5}).{0,18}(?:h|height)[_=/:-]?(\d{2,5})"#,
            #"(?i)[@_/?&](?:h|height)[_=/:-]?(\d{2,5}).{0,18}(?:w|width)[_=/:-]?(\d{2,5})"#
        ]

        for (index, pattern) in candidates.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  match.numberOfRanges >= 3,
                  let firstRange = Range(match.range(at: 1), in: normalized),
                  let secondRange = Range(match.range(at: 2), in: normalized),
                  let first = Double(normalized[firstRange]),
                  let second = Double(normalized[secondRange]),
                  first > 0,
                  second > 0
            else { continue }

            let width = index == 0 ? first : second
            let height = index == 0 ? second : first
            let ratio = width / height
            guard ratio >= 0.05, ratio <= 20 else { continue }
            return ratio
        }

        return nil
    }

    private func biliImageView2URL(width: Int, height: Int) -> String {
        let base = biliImageBaseURL()
        return "\(base)?imageView2/2/w/\(width)/h/\(height)/format/webp"
    }

    private static func biliThumbnailPixelLength(
        _ points: CGFloat,
        scale: CGFloat,
        minimum: Int = 96,
        maximum: Int
    ) -> Int {
        let scaled = Int(ceil(Swift.max(points, 1) * Swift.max(scale, 1)))
        let bucket = 16
        let bucketed = ((scaled + bucket - 1) / bucket) * bucket
        return Swift.min(Swift.max(bucketed, minimum), maximum)
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
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    nonisolated func decodeLossyDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
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

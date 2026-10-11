import Foundation

nonisolated struct UploaderSpaceRequestIdentity: Hashable, Sendable {
    let accountMID: Int?
    let credentialVersion: Int
    let isLoggedIn: Bool
    let isPurposeEnabled: Bool
    let guestModeEnabled: Bool

    init(_ snapshot: BiliAPIClient.RequestSnapshot) {
        accountMID = snapshot.currentUserMID
        credentialVersion = snapshot.playbackCredentialVersion
        isLoggedIn = snapshot.isLoggedIn
        isPurposeEnabled = snapshot.isAccountPurposeEnabled
        guestModeEnabled = snapshot.guestModeEnabled
    }

    func ownsSpace(mid: Int) -> Bool {
        isLoggedIn && isPurposeEnabled && !guestModeEnabled && accountMID == mid && mid > 0
    }
}

// Decode the existing APP space response separately from the legacy profile model.
nonisolated struct UploaderSpaceOverview: Decodable, Hashable, Sendable {
    let profile: UploaderProfile
    let backgroundURL: String?
    let nightBackgroundURL: String?
    let level: Int?
    let vipLabel: String?
    let verification: String?
    let location: String?
    let availableTabIDs: [String]
    let archive: UploaderSpaceVideoGroup?
    let likes: UploaderSpaceVideoGroup?
    let coins: UploaderSpaceVideoGroup?
    let favorites: UploaderSpaceFavoriteGroup?
    let bangumi: UploaderSpaceVideoGroup?
    let favoritesDecodingFailed: Bool
    let bangumiDecodingFailed: Bool
    let privacy: UploaderSpacePrivacy?

    enum CodingKeys: String, CodingKey {
        case archive, season, setting, card
        case likes = "like_archive"
        case coins = "coin_archive"
        case favorites = "favourite2"
    }

    init(from decoder: Decoder) throws {
        if let decodedProfile = try? UploaderProfile(from: decoder) {
            profile = decodedProfile
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profile = UploaderProfile(from: try container.decode(UploaderCard.self, forKey: .card))
        }
        let root = try DynamicJSONValue(from: decoder).objectValueForDynamicParsing ?? [:]
        let card = root["card"]?.objectValueForDynamicParsing ?? [:]
        let images = root["images"]?.objectValueForDynamicParsing ?? [:]
        backgroundURL = images["imgUrl"]?.textValueForDynamicParsing
        nightBackgroundURL = images["night_imgurl"]?.textValueForDynamicParsing
        level = card["level_info"]?.objectValueForDynamicParsing?["current_level"]?.intValueForDynamicParsing
        let vip = card["vip"]?.objectValueForDynamicParsing
        vipLabel = vip?["status"]?.intValueForDynamicParsing == 1
            ? vip?["label"]?.objectValueForDynamicParsing?["text"]?.textValueForDynamicParsing : nil
        let official = card["official_verify"]?.objectValueForDynamicParsing
        verification = official?["type"]?.intValueForDynamicParsing.map { $0 >= 0 } == true
            ? official?["desc"]?.textValueForDynamicParsing : nil
        if case .array(let tags) = card["space_tag"] {
            location = tags.compactMap(\.objectValueForDynamicParsing)
                .first { $0["type"]?.textValueForDynamicParsing == "location" }?["title"]?.textValueForDynamicParsing
        } else { location = nil }
        if case .array(let tabs) = root["tab2"] {
            availableTabIDs = tabs.compactMap { $0.objectValueForDynamicParsing?["param"]?.textValueForDynamicParsing }
        } else { availableTabIDs = [] }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A malformed optional module must not discard the other space content.
        archive = try? container.decodeIfPresent(UploaderSpaceVideoGroup.self, forKey: .archive)
        likes = try? container.decodeIfPresent(UploaderSpaceVideoGroup.self, forKey: .likes)
        coins = try? container.decodeIfPresent(UploaderSpaceVideoGroup.self, forKey: .coins)
        favorites = try? container.decodeIfPresent(UploaderSpaceFavoriteGroup.self, forKey: .favorites)
        bangumi = try? container.decodeIfPresent(UploaderSpaceVideoGroup.self, forKey: .season)
        favoritesDecodingFailed = container.contains(.favorites)
            && (try? container.decodeNil(forKey: .favorites)) == false && favorites == nil
        bangumiDecodingFailed = container.contains(.season)
            && (try? container.decodeNil(forKey: .season)) == false && bangumi == nil
        privacy = try? container.decodeIfPresent(UploaderSpacePrivacy.self, forKey: .setting)
    }

    var hasPreviewContent: Bool {
        [archive, likes, coins].contains { group in
            group?.items.contains { $0.video(defaultMID: 0) != nil } == true
        } || bangumi?.items.contains { $0.seasonID != nil } == true
            || favorites?.items.contains { $0.folder.id > 0 } == true
    }
}

nonisolated struct UploaderSpaceVideoGroup: Decodable, Hashable, Sendable {
    let count: Int?
    let items: [UploaderSpaceVideoPreview]
    enum CodingKeys: String, CodingKey { case count; case items = "item" }

    init(count: Int?, items: [UploaderSpaceVideoPreview]) {
        self.count = count
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.decodeLossyIntIfPresent(forKey: .count)
        items = try c.decode([UploaderSpaceVideoPreview].self, forKey: .items)
    }
}

nonisolated struct UploaderSpaceVideoPreview: Decodable, Hashable, Sendable {
    let archive: UploaderAppArchiveItem
    let cardGoto: String?
    let isPGC: Bool
    fileprivate let webSeasonID: Int?
    enum CodingKeys: String, CodingKey {
        case cardGoto = "goto"; case isPGC = "is_pgc"; case webSeasonID = "season_id"
    }

    init(from decoder: Decoder) throws {
        archive = try UploaderAppArchiveItem(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardGoto = c.decodeLossyStringIfPresent(forKey: .cardGoto)
        webSeasonID = c.decodeLossyIntIfPresent(forKey: .webSeasonID)
        isPGC = c.decodeLossyBoolIfPresent(forKey: .isPGC) == true || webSeasonID != nil
    }

    func video(defaultMID: Int) -> VideoItem? {
        guard !isPGC, cardGoto == nil || cardGoto == "av" || cardGoto == "video" else { return nil }
        return archive.asVideoItem(defaultMID: defaultMID)
    }

    var seasonID: Int? {
        if let webSeasonID { return webSeasonID > 0 ? webSeasonID : nil }
        guard cardGoto == nil || cardGoto == "bangumi" || cardGoto == "pgc" || isPGC,
              let id = archive.param.flatMap(Int.init), id > 0 else { return nil }
        return id
    }
}

nonisolated struct UploaderSpaceFavoriteGroup: Decodable, Hashable, Sendable {
    let count: Int?
    let items: [UploaderSpaceFavoritePreview]
    enum CodingKeys: String, CodingKey { case count; case items = "item" }
    init(folders: [FavoriteFolder]) {
        count = folders.count
        items = folders.map(UploaderSpaceFavoritePreview.init(folder:))
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.decodeLossyIntIfPresent(forKey: .count)
        items = try c.decode([UploaderSpaceFavoritePreview].self, forKey: .items)
    }
}

nonisolated struct UploaderSpaceFavoritePreview: Decodable, Hashable, Sendable {
    let folder: FavoriteFolder
    let count: Int?
    let isPublic: Bool?
    enum CodingKeys: String, CodingKey { case count; case isPublic = "is_public" }
    init(folder: FavoriteFolder) {
        self.folder = folder
        count = folder.mediaCount
        isPublic = folder.attr.map { ($0 & 1) == 0 }
    }
    init(from decoder: Decoder) throws {
        folder = try FavoriteFolder(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.decodeLossyIntIfPresent(forKey: .count)
        isPublic = c.decodeLossyBoolIfPresent(forKey: .isPublic)
    }
}

nonisolated struct UploaderSpaceBangumiList: Decodable {
    let total: Int?
    let list: [UploaderSpaceVideoPreview]
    enum CodingKeys: String, CodingKey { case total, list }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.decodeLossyIntIfPresent(forKey: .total)
        list = try c.decode([UploaderSpaceVideoPreview].self, forKey: .list)
        guard list.allSatisfy({ ($0.webSeasonID ?? 0) > 0 }) else {
            throw DecodingError.dataCorruptedError(forKey: .list, in: c, debugDescription: "Missing valid season_id")
        }
    }
}

nonisolated struct UploaderSpaceFavoriteList: Decodable {
    let list: [FavoriteFolder]
    enum CodingKeys: String, CodingKey { case count, list }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let count = c.decodeLossyIntIfPresent(forKey: .count)
        if let folders = try c.decodeIfPresent([FavoriteFolder].self, forKey: .list),
           !folders.isEmpty || (count ?? 0) == 0 {
            list = folders
        } else if count == 0, c.contains(.list), try c.decodeNil(forKey: .list) {
            // The all-folders endpoint returns list:null with count:0 when truly empty.
            list = []
        } else {
            throw DecodingError.dataCorruptedError(forKey: .list, in: c, debugDescription: "Missing favorite folders")
        }
    }
}

nonisolated struct UploaderSpacePrivacy: Decodable, Hashable, Sendable {
    let favoritesVisible: Bool?
    let likesVisible: Bool?
    let coinsVisible: Bool?
    let bangumiVisible: Bool?
    enum CodingKeys: String, CodingKey {
        case favoritesVisible = "fav_video"
        case likesVisible = "likes_video"
        case coinsVisible = "coins_video"
        case bangumiVisible = "bangumi"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favoritesVisible = c.decodeLossyBoolIfPresent(forKey: .favoritesVisible)
        likesVisible = c.decodeLossyBoolIfPresent(forKey: .likesVisible)
        coinsVisible = c.decodeLossyBoolIfPresent(forKey: .coinsVisible)
        bangumiVisible = c.decodeLossyBoolIfPresent(forKey: .bangumiVisible)
    }
}

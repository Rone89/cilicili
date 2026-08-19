import Foundation

nonisolated struct InteractionRequestContext: Sendable {
    let cookieHeader: String
    let appAccessKey: String?
    let isLoggedIn: Bool
    let csrfToken: String?
    let currentUserMID: Int?
}

nonisolated struct AccountLibraryRequestContext: Sendable {
    let cookieHeader: String
    let isLoggedIn: Bool
    let currentUserMID: Int?
}

nonisolated struct HomeRecommendRequestContext: Sendable {
    let cookieHeader: String
    let anonymousCookieHeader: String
    let appAccessKey: String?
    let identityKey: String
    let isLoggedIn: Bool
    let guestModeEnabled: Bool
    let feedSource: HomeRecommendFeedSourcePreference
}

nonisolated struct PlaybackHistoryRequestContext: Sendable {
    let cookieHeader: String
    let appAccessKey: String?
    let isLoggedIn: Bool
    let csrfToken: String?
    let isAccountPurposeEnabled: Bool
}

nonisolated struct VideoListenPlaylistRequestContext: Sendable {
    let cookieHeader: String
    let anonymousCookieHeader: String
    let appAccessKey: String?
    let guestModeEnabled: Bool
}

nonisolated struct BiliAPITransportRequestContext: Sendable {
    let cookieHeader: String
    let anonymousCookieHeader: String
    let isLoggedIn: Bool
    let csrfToken: String?
    let guestModeEnabled: Bool
}

nonisolated extension BiliAPIClient {
    func transportRequestContext(
        purpose: BiliAccountPurpose = .main
    ) async -> BiliAPITransportRequestContext {
        let snapshot = await requestSnapshot(purpose: purpose)
        return BiliAPITransportRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            isLoggedIn: snapshot.isLoggedIn,
            csrfToken: snapshot.csrfToken,
            guestModeEnabled: snapshot.guestModeEnabled
        )
    }

    func playbackHistoryRequestContext() async -> PlaybackHistoryRequestContext {
        let snapshot = await requestSnapshot(purpose: .historyWrite)
        return PlaybackHistoryRequestContext(
            cookieHeader: snapshot.cookieHeader,
            appAccessKey: snapshot.appAccessKey,
            isLoggedIn: snapshot.isLoggedIn,
            csrfToken: snapshot.csrfToken,
            isAccountPurposeEnabled: snapshot.isAccountPurposeEnabled
        )
    }

    func videoListenPlaylistRequestContext() async -> VideoListenPlaylistRequestContext {
        let snapshot = await requestSnapshot(purpose: .playback)
        return VideoListenPlaylistRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            guestModeEnabled: snapshot.guestModeEnabled
        )
    }

    func interactionRequestContext(
        purpose: BiliAccountPurpose = .interaction
    ) async -> InteractionRequestContext {
        let snapshot = await requestSnapshot(purpose: purpose)
        return InteractionRequestContext(
            cookieHeader: snapshot.cookieHeader,
            appAccessKey: snapshot.appAccessKey,
            isLoggedIn: snapshot.isLoggedIn,
            csrfToken: snapshot.csrfToken,
            currentUserMID: snapshot.currentUserMID
        )
    }

    func playbackAPIRequestContext() async -> PlaybackAPIRequestContext {
        let snapshot = await requestSnapshot(purpose: .playback)
        return PlaybackAPIRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            effectivePreferredVideoQuality: snapshot.effectivePreferredVideoQuality,
            playbackStreamSourcePreference: snapshot.playbackStreamSourcePreference,
            isLoggedIn: snapshot.isLoggedIn,
            currentUserMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled,
            playbackCredentialVersion: snapshot.playbackCredentialVersion,
            isAccountPurposeEnabled: snapshot.isAccountPurposeEnabled
        )
    }

    func videoContentRequestContext() async -> VideoContentRequestContext {
        let snapshot = await requestSnapshot()
        return VideoContentRequestContext(
            cookieHeader: snapshot.cookieHeader,
            guestModeCookieHeader: snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : nil,
            credentialVersion: snapshot.playbackCredentialVersion
        )
    }

    func homeRecommendRequestContext() async -> HomeRecommendRequestContext {
        let snapshot = await requestSnapshot()
        return HomeRecommendRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            identityKey: snapshot.homeRecommendIdentityKey,
            isLoggedIn: snapshot.isLoggedIn,
            guestModeEnabled: snapshot.guestModeEnabled,
            feedSource: snapshot.homeRecommendFeedSourcePreference
        )
    }

    func accountLibraryRequestContext(
        purpose: BiliAccountPurpose
    ) async -> AccountLibraryRequestContext {
        let snapshot = await requestSnapshot(purpose: purpose)
        return AccountLibraryRequestContext(
            cookieHeader: snapshot.cookieHeader,
            isLoggedIn: snapshot.isLoggedIn,
            currentUserMID: snapshot.currentUserMID
        )
    }

    func liveAccountRequestIdentity() async -> (cookieHeader: String, currentUserMID: Int?) {
        let snapshot = await requestSnapshot()
        return (snapshot.cookieHeader, snapshot.currentUserMID)
    }

    func dynamicFeedRequestContext() async -> (
        cookieHeader: String,
        anonymousCookieHeader: String,
        isLoggedIn: Bool,
        currentUserMID: Int?
    ) {
        let snapshot = await requestSnapshot(purpose: .dynamicFeed)
        return (
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            isLoggedIn: snapshot.isLoggedIn,
            currentUserMID: snapshot.currentUserMID
        )
    }

    func anonymousCookieHeader(
        purpose: BiliAccountPurpose = .main
    ) async -> String {
        let snapshot = await requestSnapshot(purpose: purpose)
        return snapshot.anonymousCookieHeader
    }

    func uploaderProfileRequestContext() async -> (
        cookieHeader: String,
        anonymousCookieHeader: String,
        appAccessKey: String?,
        isLoggedIn: Bool
    ) {
        let snapshot = await requestSnapshot()
        return (
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            isLoggedIn: snapshot.isLoggedIn
        )
    }
}

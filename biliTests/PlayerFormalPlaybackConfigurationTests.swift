import XCTest
@testable import bili

final class PlayerFormalPlaybackConfigurationTests: XCTestCase {
    func testStoredKernelMigratesLegacyKSPlayerToAVPlayer() {
        let defaults = makeUserDefaults()
        defaults.set(PlayerKernelType.ksPlayer.rawValue, forKey: PlayerKernelType.storageKey)

        XCTAssertEqual(PlayerKernelType.stored(in: defaults), .avPlayer)
    }

    func testStoredRenderingEnginePreferenceMigratesLegacyValuesToAVPlayer() {
        let defaults = makeUserDefaults()

        defaults.set(PlayerRenderingEnginePreference.ksPlayer.rawValue, forKey: PlayerRenderingEnginePreference.storageKey)
        XCTAssertEqual(PlayerRenderingEnginePreference.stored(in: defaults), .avPlayer)

        defaults.set(PlayerRenderingEnginePreference.automatic.rawValue, forKey: PlayerRenderingEnginePreference.storageKey)
        XCTAssertEqual(PlayerRenderingEnginePreference.stored(in: defaults), .avPlayer)
    }

    @MainActor
    func testPlayerSettingsPersistsAVPlayerWhenLegacyKernelIsSet() {
        let defaults = makeUserDefaults()
        let settings = PlayerSettings(userDefaults: defaults)

        settings.setPreferredKernel(.ksPlayer)

        XCTAssertEqual(settings.preferredKernel, .avPlayer)
        XCTAssertEqual(defaults.string(forKey: PlayerKernelType.storageKey), PlayerKernelType.avPlayer.rawValue)
    }

    @MainActor
    func testPlayerSettingsMigratesLegacyAV1CodecPreferenceToAuto() {
        let defaults = makeUserDefaults()
        defaults.set(VideoCodecPreference.forceAV1.rawValue, forKey: VideoCodecPreference.storageKey)

        let settings = PlayerSettings(userDefaults: defaults)
        settings.reload()
        settings.setVideoCodecPreference(.forceAV1)

        XCTAssertEqual(settings.videoCodecPreference, .auto)
        XCTAssertEqual(defaults.string(forKey: VideoCodecPreference.storageKey), VideoCodecPreference.auto.rawValue)
    }

    @MainActor
    func testCoreVideoPlayerManagerUsesAVPlayerForLegacyKernelRequest() {
        let defaults = makeUserDefaults()
        let settings = PlayerSettings(userDefaults: defaults)
        let manager = CoreVideoPlayerManager(settings: settings)

        XCTAssertTrue(manager.makeRenderingEngine(kernel: .ksPlayer) is AVPlayerHLSBridgeEngine)
        XCTAssertTrue(manager.makePlayer(kernel: .ksPlayer) is AVPlayerAdapter)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "cc.bili.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

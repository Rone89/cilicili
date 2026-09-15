import XCTest

@testable import bili

class H264PlaybackTestCase: XCTestCase {
    private var previousCodecPreference: Any?

    override func setUp() {
        super.setUp()
        previousCodecPreference = UserDefaults.standard.object(
            forKey: VideoCodecPreference.storageKey
        )
        UserDefaults.standard.set(
            VideoCodecPreference.forceH264.rawValue,
            forKey: VideoCodecPreference.storageKey
        )
    }

    override func tearDown() {
        if let previousCodecPreference {
            UserDefaults.standard.set(
                previousCodecPreference,
                forKey: VideoCodecPreference.storageKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: VideoCodecPreference.storageKey)
        }
        super.tearDown()
    }
}

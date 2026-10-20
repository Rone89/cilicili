import Foundation

/// One queue preserves submission order across LibraryStore instances. Encoding
/// and UserDefaults writes never run in a player's main-actor progress callback.
nonisolated final class PlaybackProgressStorage: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "cc.bili.playback-progress", qos: .utility)
    private let defaults: UserDefaults
    private let key: String
    private let encode: @Sendable ([String: StoredPlaybackProgress]) throws -> Data

    init(
        defaults: UserDefaults,
        key: String,
        encode: @escaping @Sendable ([String: StoredPlaybackProgress]) throws -> Data = {
            try JSONEncoder().encode($0)
        }
    ) {
        self.defaults = defaults
        self.key = key
        self.encode = encode
    }

    func save(_ progress: [String: StoredPlaybackProgress]) {
        Self.queue.async { [self] in
            guard !progress.isEmpty else {
                defaults.removeObject(forKey: key)
                return
            }
            // An encoding error must not erase the last successfully saved state.
            guard let data = try? encode(progress) else { return }
            defaults.set(data, forKey: key)
        }
    }

    func waitForPendingOperations() async {
        await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume() }
        }
    }
}

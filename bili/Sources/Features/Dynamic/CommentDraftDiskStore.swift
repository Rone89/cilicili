import Foundation

nonisolated struct StoredCommentDraft: Codable, Sendable {
    nonisolated struct Part: Codable, Sendable {
        let kind: String
        let value: String
    }

    let key: ScopedCommentDraftKey
    let parts: [Part]
    let selectionLocation: Int?
    let selectionLength: Int?
    let authorName: String?
    let imageCount: Int
    let updatedAt: Date
}

/// Serial disk access keeps JSON work and atomic writes off the main actor.
/// Attachments and authentication credentials are never included.
actor CommentDraftDiskStore {
    nonisolated private struct Archive: Codable, Sendable {
        let version: Int
        let drafts: [StoredCommentDraft]
    }

    private let directory: URL
    private let maximumBytes: Int
    private var resetsBeforeLoading: Bool
    private var latestRevision: UInt64 = 0

    init(directory: URL, maximumBytes: Int = 1024 * 1024, resetsBeforeLoading: Bool = false) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.resetsBeforeLoading = resetsBeforeLoading
    }

    func load() throws -> [StoredCommentDraft] {
        let manager = FileManager.default
        if resetsBeforeLoading {
            resetsBeforeLoading = false
            if manager.fileExists(atPath: directory.path) {
                try manager.removeItem(at: directory)
            }
        }
        let file = directory.appendingPathComponent("drafts-v1.json")
        guard manager.fileExists(atPath: file.path) else { return [] }
        let attributes = try manager.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
        guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return archive.drafts
    }

    func save(_ drafts: [StoredCommentDraft], revision: UInt64 = 0) throws {
        guard revision >= latestRevision else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(values)
        let file = directory.appendingPathComponent("drafts-v1.json")
        if drafts.isEmpty {
            if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
            latestRevision = revision
            return
        }
        let data = try JSONEncoder().encode(Archive(version: 1, drafts: drafts))
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        latestRevision = revision
    }
}

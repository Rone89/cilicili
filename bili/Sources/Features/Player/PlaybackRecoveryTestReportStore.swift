import Combine
import Foundation

nonisolated protocol PlaybackRecoveryTestReportPersistence: Sendable {
    func read() async throws -> PlaybackRecoveryTestReport?
    func write(_ report: PlaybackRecoveryTestReport, revision: UInt64) async throws
}

actor PlaybackRecoveryTestReportDisk: PlaybackRecoveryTestReportPersistence {
    private let url: URL
    private var newestRevision: UInt64 = 0

    init(url: URL = URL.applicationSupportDirectory
        .appending(path: "PlaybackRecoveryTests", directoryHint: .isDirectory)
        .appending(path: "latest.json")) {
        self.url = url
    }

    func read() throws -> PlaybackRecoveryTestReport? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlaybackRecoveryTestReport.self, from: data)
    }

    func write(_ report: PlaybackRecoveryTestReport, revision: UInt64) throws {
        guard revision >= newestRevision else { return }
        newestRevision = revision
        let data = Data(report.exportText.utf8)
        guard !data.isEmpty, data.count <= 1_048_576 else { throw CocoaError(.fileWriteUnknown) }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directoryURL = directory
        try directoryURL.setResourceValues(values)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor
final class PlaybackRecoveryTestReportStore: ObservableObject {
    static let shared = PlaybackRecoveryTestReportStore()
    @Published private(set) var report: PlaybackRecoveryTestReport?
    @Published private(set) var persistenceError: String?
    private let disk: any PlaybackRecoveryTestReportPersistence
    private var revision: UInt64 = 0
    private var pendingWrite: Task<Void, Never>?

    init(disk: any PlaybackRecoveryTestReportPersistence = PlaybackRecoveryTestReportDisk()) {
        self.disk = disk
        Task { @MainActor [weak self, disk] in
            do {
                guard var loaded = try await disk.read(), let self, self.revision == 0 else { return }
                if loaded.status == "running" {
                    loaded.status = "interrupted"
                    loaded.reason = "上次测试未正常结束"
                    loaded.endedAt = Date()
                    if loaded.trials.last?.outcome == "running" {
                        loaded.trials[loaded.trials.count - 1].outcome = "interrupted"
                        loaded.trials[loaded.trials.count - 1].reason = loaded.reason
                    }
                    self.report = loaded
                    self.persist(loaded)
                } else {
                    self.report = loaded
                }
            } catch {
                guard let self, self.revision == 0 else { return }
                self.persistenceError = "上次报告读取失败；新测试仍可开始。"
            }
        }
    }

    func begin(_ report: PlaybackRecoveryTestReport) {
        self.report = report
        persistenceError = nil
        persist(report)
    }

    func update(_ report: PlaybackRecoveryTestReport) {
        guard self.report?.runID == report.runID else { return }
        self.report = report
        persist(report)
    }

    func flush() async { await pendingWrite?.value }

    private func persist(_ report: PlaybackRecoveryTestReport) {
        revision &+= 1
        let requestedRevision = revision
        pendingWrite = Task { @MainActor [weak self, disk] in
            do {
                try await disk.write(report, revision: requestedRevision)
                guard let self, self.revision == requestedRevision else { return }
                self.persistenceError = nil
            } catch {
                guard let self, self.revision == requestedRevision else { return }
                self.persistenceError = "报告暂未保存，请立即复制当前报告。"
            }
        }
    }
}

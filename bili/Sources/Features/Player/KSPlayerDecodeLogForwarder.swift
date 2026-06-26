import Foundation
import KSPlayer
import OSLog

final class KSPlayerDecodeLogForwarder: LogHandler, @unchecked Sendable {
    static let shared = KSPlayerDecodeLogForwarder()

    private struct Context: Sendable {
        let metricsID: String
        let title: String
    }

    private let lock = NSLock()
    private let systemLogger = Logger(subsystem: "cc.cilicili.player", category: "KSDecode")
    private let fallbackLogger = KSPlayer.OSLog(lable: "KSPlayer")
    private var context: Context?

    private init() {}

    func setActivePlayback(metricsID: String, title: String) {
        lock.lock()
        context = Context(metricsID: metricsID, title: title)
        lock.unlock()
    }

    func clearActivePlayback(metricsID: String? = nil) {
        lock.lock()
        if let metricsID {
            if context?.metricsID == metricsID {
                context = nil
            }
        } else {
            context = nil
        }
        lock.unlock()
    }

    func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        fallbackLogger.log(level: level, message: message, file: file, function: function, line: line)

        let cleanMessage = Self.normalized(message.description)
        guard Self.isDecodeDiagnostic(cleanMessage) else { return }

        let entry = "level=\(level.description) \(cleanMessage)"
        systemLogger.info("\(entry, privacy: .public)")
        print("[KSDecode] \(entry)")

        let currentContext: Context?
        lock.lock()
        currentContext = context
        lock.unlock()

        guard let currentContext else { return }
        Task { @MainActor in
            PlayerMetricsLog.record(
                .decodeLog,
                metricsID: currentContext.metricsID,
                title: currentContext.title,
                message: entry
            )
        }
    }

    private static func normalized(_ message: String) -> String {
        let collapsed = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 280 else { return collapsed }
        return "\(collapsed.prefix(280))..."
    }

    private static func isDecodeDiagnostic(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("decoder=")
            || lowercased.contains("videotoolbox")
            || lowercased.contains("vtdecompressionsession")
            || lowercased.contains("hardwaredecode")
            || lowercased.contains("hardware accelerated av1")
            || lowercased.contains("software decompression")
            || lowercased.contains("av1_videotoolbox")
            || lowercased.contains("decoder did failed")
    }
}

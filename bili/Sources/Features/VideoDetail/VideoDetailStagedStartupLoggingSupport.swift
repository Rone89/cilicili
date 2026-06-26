import Foundation
import OSLog

extension VideoDetailViewModel {
    func logStagedStartupDecision(_ message: String) {
        PlayerMetricsLog.logger.info(
            "stagedStartup \(message, privacy: .public) bvid=\(self.detail.bvid, privacy: .public)"
        )
    }

    nonisolated static func formattedFrameRate(_ frameRate: Double) -> String {
        guard frameRate > 0 else { return "-" }
        return String(format: "%.0f", frameRate)
    }
}

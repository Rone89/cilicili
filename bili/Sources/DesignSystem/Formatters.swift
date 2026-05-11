import Foundation

enum BiliFormatters {
    static func compactCount(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 100_000_000 {
            return String(format: "%.1f亿", Double(value) / 100_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        return String(value)
    }

    static func duration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "--:--" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    static func relativeTime(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let seconds = max(0, Int(Date().timeIntervalSince(date)))

        if seconds < 60 {
            return "刚刚"
        }
        if seconds < 3600 {
            return "\(seconds / 60)分钟前"
        }
        if seconds < 86_400 {
            return "\(seconds / 3600)小时前"
        }
        if seconds < 604_800 {
            return "\(seconds / 86_400)天前"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }

    static func publishDate(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

import Foundation

/// Optional metadata returned with a comment; never performs a location lookup.
nonisolated struct CommentReplyControl: Decodable, Hashable, Sendable {
    let location: String?

    enum CodingKeys: String, CodingKey {
        case location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        location = try? container.decodeIfPresent(String.self, forKey: .location)
    }
}

extension Comment {
    /// Keep the service's label, including its IP-region prefix when supplied.
    nonisolated var locationText: String? {
        guard let value = replyControl?.location else { return nil }
        let text = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    nonisolated func metadataText(timeText: String) -> String {
        [timeText, locationText ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

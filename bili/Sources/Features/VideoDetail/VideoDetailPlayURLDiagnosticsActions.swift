import Foundation

extension VideoDetailViewModel {
    func playURLLoadedMessage(
        source: String,
        data: PlayURLData,
        note: String? = nil,
        error: Error? = nil
    ) -> String {
        let playableVariants = data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            .filter(\.isPlayable)
        var parts = [
            "source=\(diagnosticToken(source))",
            "variants=\(playableVariants.count)",
            "qualities=\(Self.qualitySummary(playableVariants))",
            "cdn=\(diagnosticToken(libraryStore.effectivePlaybackCDNPreference.rawValue))"
        ]
        if let note, !note.isEmpty {
            parts.append("note=\(diagnosticToken(note))")
        }
        if let error {
            parts.append("error=\(diagnosticToken(error.localizedDescription))")
        }
        return parts.joined(separator: " ")
    }

    func diagnosticToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        return String(trimmed.map { character in
            character.isWhitespace || character == "|" ? "_" : character
        })
    }
}

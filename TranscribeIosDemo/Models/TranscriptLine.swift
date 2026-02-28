import Foundation

/// A single line of transcribed text.
struct TranscriptLine: Identifiable {
    let id = UUID()
    let text: String
    let isPartial: Bool
    let timestamp: Date

    init(text: String, isPartial: Bool) {
        self.text = text
        self.isPartial = isPartial
        self.timestamp = Date()
    }
}

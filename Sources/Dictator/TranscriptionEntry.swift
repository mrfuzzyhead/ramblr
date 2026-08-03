import Foundation

struct TranscriptionEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let pasted: Bool
    /// Length of the recorded audio clip, in milliseconds.
    let audioDurationMs: Int?
    /// Time from transcription request start until the API response, in milliseconds.
    let transcriptionMs: Int?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        pasted: Bool,
        audioDurationMs: Int? = nil,
        transcriptionMs: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.pasted = pasted
        self.audioDurationMs = audioDurationMs
        self.transcriptionMs = transcriptionMs
    }
}

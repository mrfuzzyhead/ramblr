import Foundation

enum TranscriptionKind: String, Codable, Equatable, Sendable {
    case dictation
    case compose
}

struct TranscriptionEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let pasted: Bool
    let kind: TranscriptionKind
    /// Length of the recorded audio clip, in milliseconds.
    let audioDurationMs: Int?
    /// Time from transcription request start until the API response, in milliseconds.
    let transcriptionMs: Int?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        pasted: Bool,
        kind: TranscriptionKind = .dictation,
        audioDurationMs: Int? = nil,
        transcriptionMs: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.pasted = pasted
        self.kind = kind
        self.audioDurationMs = audioDurationMs
        self.transcriptionMs = transcriptionMs
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, pasted, kind, audioDurationMs, transcriptionMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        pasted = try container.decode(Bool.self, forKey: .pasted)
        kind = try container.decodeIfPresent(TranscriptionKind.self, forKey: .kind) ?? .dictation
        audioDurationMs = try container.decodeIfPresent(Int.self, forKey: .audioDurationMs)
        transcriptionMs = try container.decodeIfPresent(Int.self, forKey: .transcriptionMs)
    }
}

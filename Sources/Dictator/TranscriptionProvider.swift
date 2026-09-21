import Foundation

enum TranscriptionProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI
    case gemini

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini 3.5 Transcribe"
        }
    }

    var settingsTitle: String {
        menuTitle
    }

    var settingsSubtitle: String {
        switch self {
        case .openAI:
            return "Transcribe with OpenAI gpt-transcribe"
        case .gemini:
            return "Transcribe with Gemini 3.5 Transcribe"
        }
    }
}

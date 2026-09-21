import Foundation

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String)
    case emptyTranscription
    case fileReadFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Gemini API key in Settings."
        case .invalidResponse:
            return "Gemini returned an unexpected response."
        case .httpStatus(let code, let body):
            if body.isEmpty { return "Gemini request failed (\(code))." }
            return "Gemini request failed (\(code)): \(body)"
        case .emptyTranscription:
            return "Transcription was empty"
        case .fileReadFailed:
            return "Could not read the recorded audio file."
        case .encodingFailed:
            return "Could not encode the Gemini transcription request."
        }
    }
}

struct GeminiService: Sendable {
    static let transcriptionModel = "gemini-3.5-transcribe"
    static let languageCode = "en-GB"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(fileURL: URL, apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GeminiServiceError.missingAPIKey }
        guard let audioData = try? Data(contentsOf: fileURL) else {
            throw GeminiServiceError.fileReadFailed
        }

        let requestBody = GeminiGenerateContentRequest(
            contents: [
                GeminiGenerateContentRequest.Content(
                    parts: [
                        GeminiGenerateContentRequest.Part(
                            inlineData: GeminiGenerateContentRequest.InlineData(
                                mimeType: "audio/mp4",
                                data: audioData.base64EncodedString()
                            )
                        )
                    ]
                )
            ],
            generationConfig: GeminiGenerateContentRequest.GenerationConfig(
                audioTranscriptionConfig: GeminiGenerateContentRequest.AudioTranscriptionConfig(
                    languageCodes: [Self.languageCode],
                    mode: "SMART"
                )
            )
        )

        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.transcriptionModel):generateContent"
        ) else {
            throw GeminiServiceError.encodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw GeminiServiceError.encodingFailed
        }

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let rawText = decoded.transcriptText
        let text = TranscriptPostProcessor.process(rawText)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiServiceError.emptyTranscription
        }
        return text
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = geminiErrorMessage(from: data) ?? (String(data: data, encoding: .utf8) ?? "")
            throw GeminiServiceError.httpStatus(http.statusCode, message)
        }
    }

    private static func geminiErrorMessage(from data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data) else {
            return nil
        }
        return decoded.error.message
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct Content: Encodable {
        let parts: [Part]
    }

    struct Part: Encodable {
        let inlineData: InlineData
    }

    struct InlineData: Encodable {
        let mimeType: String
        let data: String
    }

    struct GenerationConfig: Encodable {
        let audioTranscriptionConfig: AudioTranscriptionConfig
    }

    struct AudioTranscriptionConfig: Encodable {
        let languageCodes: [String]
        let mode: String
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [Candidate]?

    var transcriptText: String {
        let parts = candidates?.first?.content?.parts ?? []

        let transcriptionTexts = parts
            .compactMap { $0.audioTranscription?.text }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !transcriptionTexts.isEmpty {
            return transcriptionTexts.joined(separator: " ")
        }

        let joined = parts.compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty {
            return joined
        }

        let words = parts
            .flatMap { $0.audioTranscription?.words ?? [] }
            .compactMap(\.word)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return words.joined(separator: " ")
    }

    struct Candidate: Decodable {
        let content: Content?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
        let audioTranscription: AudioTranscription?
    }

    struct AudioTranscription: Decodable {
        let text: String?
        let words: [Word]?
    }

    struct Word: Decodable {
        let word: String?
    }
}

private struct GeminiErrorEnvelope: Decodable {
    let error: GeminiAPIError
}

private struct GeminiAPIError: Decodable {
    let message: String?
    let code: Int?
    let status: String?
}

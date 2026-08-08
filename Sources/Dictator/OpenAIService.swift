import Foundation

enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String)
    case emptyTranscription
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key in Settings."
        case .invalidResponse:
            return "OpenAI returned an unexpected response."
        case .httpStatus(let code, let body):
            if body.isEmpty { return "OpenAI request failed (\(code))." }
            return "OpenAI request failed (\(code)): \(body)"
        case .emptyTranscription:
            return "Transcription was empty"
        case .fileReadFailed:
            return "Could not read the recorded audio file."
        }
    }
}

struct OpenAIService: Sendable {
    static let transcriptionModel = "gpt-transcribe"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(fileURL: URL, apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw OpenAIServiceError.missingAPIKey }
        guard let audioData = try? Data(contentsOf: fileURL) else {
            throw OpenAIServiceError.fileReadFailed
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(multipartField(name: "model", value: Self.transcriptionModel, boundary: boundary))
        body.append(multipartField(name: "response_format", value: "json", boundary: boundary))
        body.append(multipartFile(
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/m4a",
            data: audioData,
            boundary: boundary
        ))
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenAIServiceError.emptyTranscription }
        return text
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIServiceError.httpStatus(http.statusCode, body)
        }
    }

    private func multipartField(name: String, value: String, boundary: String) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(value)\r\n".data(using: .utf8)!)
        return data
    }

    private func multipartFile(
        name: String,
        filename: String,
        mimeType: String,
        data fileData: Data,
        boundary: String
    ) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        return data
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

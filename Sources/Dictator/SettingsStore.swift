import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let shortcut = "shortcut"
        static let dictateAndSendShortcut = "dictateAndSendShortcut"
        static let legacyComposeShortcut = "composeShortcut"
        static let microphoneUID = "microphoneUID"
        static let transcriptionProvider = "transcriptionProvider"
        static let muteSpeakersWhileRecording = "muteSpeakersWhileRecording"
        static let history = "history"
        static let seededAPIKey = "seededAPIKey"
        static let seededGeminiAPIKey = "seededGeminiAPIKey"
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxHistory = 50

    @Published var apiKey: String {
        didSet { OpenAIKeyStore.save(apiKey) }
    }

    @Published var geminiAPIKey: String {
        didSet { GeminiKeyStore.save(geminiAPIKey) }
    }

    @Published var transcriptionProvider: TranscriptionProvider {
        didSet { defaults.set(transcriptionProvider.rawValue, forKey: Keys.transcriptionProvider) }
    }

    @Published var shortcut: KeyboardShortcut {
        didSet { persistShortcut() }
    }

    @Published var dictateAndSendShortcut: KeyboardShortcut {
        didSet { persistDictateAndSendShortcut() }
    }

    @Published var microphoneUID: String? {
        didSet { defaults.set(microphoneUID, forKey: Keys.microphoneUID) }
    }

    @Published var muteSpeakersWhileRecording: Bool {
        didSet { defaults.set(muteSpeakersWhileRecording, forKey: Keys.muteSpeakersWhileRecording) }
    }

    @Published private(set) var history: [TranscriptionEntry] {
        didSet { persistHistory() }
    }

    private init() {
        let storedKey = OpenAIKeyStore.read()
        let resolvedOpenAIKey: String
        if storedKey.isEmpty {
            let seeded = EnvLoader.apiKey(named: "OPENAI_API_KEY")
            if !seeded.isEmpty {
                OpenAIKeyStore.save(seeded)
                resolvedOpenAIKey = seeded
                defaults.set(true, forKey: Keys.seededAPIKey)
            } else {
                resolvedOpenAIKey = ""
            }
        } else {
            resolvedOpenAIKey = storedKey
        }
        apiKey = resolvedOpenAIKey

        let storedGeminiKey = GeminiKeyStore.read()
        let resolvedGeminiKey: String
        if storedGeminiKey.isEmpty {
            let seeded = EnvLoader.apiKey(named: "GEMINI_API_KEY")
            if !seeded.isEmpty {
                GeminiKeyStore.save(seeded)
                resolvedGeminiKey = seeded
                defaults.set(true, forKey: Keys.seededGeminiAPIKey)
            } else {
                resolvedGeminiKey = ""
            }
        } else {
            resolvedGeminiKey = storedGeminiKey
        }
        geminiAPIKey = resolvedGeminiKey

        if let rawProvider = defaults.string(forKey: Keys.transcriptionProvider),
           let provider = TranscriptionProvider(rawValue: rawProvider) {
            transcriptionProvider = provider
        } else if resolvedOpenAIKey.isEmpty && !resolvedGeminiKey.isEmpty {
            transcriptionProvider = .gemini
        } else {
            transcriptionProvider = .openAI
        }

        if let data = defaults.data(forKey: Keys.shortcut),
           let decoded = try? decoder.decode(KeyboardShortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = .defaultDictationShortcut
        }

        if let data = defaults.data(forKey: Keys.dictateAndSendShortcut),
           let decoded = try? decoder.decode(KeyboardShortcut.self, from: data) {
            dictateAndSendShortcut = decoded
        } else if let data = defaults.data(forKey: Keys.legacyComposeShortcut),
                  let decoded = try? decoder.decode(KeyboardShortcut.self, from: data) {
            dictateAndSendShortcut = decoded
        } else {
            dictateAndSendShortcut = .defaultDictateAndSendShortcut
        }

        microphoneUID = defaults.string(forKey: Keys.microphoneUID)

        if defaults.object(forKey: Keys.muteSpeakersWhileRecording) == nil {
            muteSpeakersWhileRecording = true
        } else {
            muteSpeakersWhileRecording = defaults.bool(forKey: Keys.muteSpeakersWhileRecording)
        }

        if let data = defaults.data(forKey: Keys.history),
           let decoded = try? decoder.decode([TranscriptionEntry].self, from: data) {
            history = decoded
        } else {
            history = []
        }
    }

    var lastTranscript: String? {
        history.first?.text
    }

    var selectedProviderAPIKey: String {
        switch transcriptionProvider {
        case .openAI:
            return apiKey
        case .gemini:
            return geminiAPIKey
        }
    }

    func prependHistory(_ entry: TranscriptionEntry) {
        var next = history
        next.insert(entry, at: 0)
        if next.count > maxHistory {
            next = Array(next.prefix(maxHistory))
        }
        history = next
    }

    func deleteHistory(id: UUID) {
        history.removeAll { $0.id == id }
    }

    func clearHistory() {
        history = []
    }

    private func persistShortcut() {
        if let data = try? encoder.encode(shortcut) {
            defaults.set(data, forKey: Keys.shortcut)
        }
    }

    private func persistDictateAndSendShortcut() {
        if let data = try? encoder.encode(dictateAndSendShortcut) {
            defaults.set(data, forKey: Keys.dictateAndSendShortcut)
        }
    }

    private func persistHistory() {
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: Keys.history)
        }
    }
}

enum EnvLoader {
    static func apiKey(named key: String) -> String {
        if let env = ProcessInfo.processInfo.environment[key],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for url in candidateEnvURLs() {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let value = parse(key: key, from: contents) {
                return value
            }
        }
        return ""
    }

    private static func candidateEnvURLs() -> [URL] {
        var urls: [URL] = []
        if let resource = Bundle.main.url(forResource: ".env", withExtension: nil) {
            urls.append(resource)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(cwd.appendingPathComponent(".env"))
        if let exe = Bundle.main.executableURL {
            urls.append(exe.deletingLastPathComponent().appendingPathComponent(".env"))
            urls.append(
                exe
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources")
                    .appendingPathComponent(".env")
            )
        }
        return urls
    }

    private static func parse(key: String, from contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            guard name == key else { continue }
            var value = String(trimmed[trimmed.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }
        return nil
    }
}

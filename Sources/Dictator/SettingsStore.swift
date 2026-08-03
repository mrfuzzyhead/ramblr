import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let shortcut = "shortcut"
        static let microphoneUID = "microphoneUID"
        static let history = "history"
        static let seededAPIKey = "seededAPIKey"
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxHistory = 50

    @Published var apiKey: String {
        didSet { OpenAIKeyStore.save(apiKey) }
    }

    @Published var shortcut: KeyboardShortcut {
        didSet { persistShortcut() }
    }

    @Published var microphoneUID: String? {
        didSet { defaults.set(microphoneUID, forKey: Keys.microphoneUID) }
    }

    @Published private(set) var history: [TranscriptionEntry] {
        didSet { persistHistory() }
    }

    private init() {
        let storedKey = OpenAIKeyStore.read()
        if storedKey.isEmpty {
            let seeded = EnvLoader.openAIAPIKey()
            if !seeded.isEmpty {
                OpenAIKeyStore.save(seeded)
                apiKey = seeded
                defaults.set(true, forKey: Keys.seededAPIKey)
            } else {
                apiKey = ""
            }
        } else {
            apiKey = storedKey
        }

        if let data = defaults.data(forKey: Keys.shortcut),
           let decoded = try? decoder.decode(KeyboardShortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = .defaultShortcut
        }

        microphoneUID = defaults.string(forKey: Keys.microphoneUID)

        if let data = defaults.data(forKey: Keys.history),
           let decoded = try? decoder.decode([TranscriptionEntry].self, from: data) {
            history = decoded
        } else {
            history = []
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

    func clearHistory() {
        history = []
    }

    private func persistShortcut() {
        if let data = try? encoder.encode(shortcut) {
            defaults.set(data, forKey: Keys.shortcut)
        }
    }

    private func persistHistory() {
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: Keys.history)
        }
    }
}

enum EnvLoader {
    static func openAIAPIKey() -> String {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for url in candidateEnvURLs() {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let value = parse(key: "OPENAI_API_KEY", from: contents) {
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
            // Dictator.app/Contents/MacOS -> Contents/Resources/.env
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

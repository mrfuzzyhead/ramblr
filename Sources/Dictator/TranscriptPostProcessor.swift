import Foundation

enum TranscriptPostProcessor {
    /// Converts spoken formatting commands into characters, normalises spacing,
    /// and always ends with a single trailing space for continued typing.
    static func process(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return " " }

        for rule in spokenCommandRules {
            result = replace(pattern: rule.pattern, with: rule.replacement, in: result)
        }

        result = normaliseSpacing(result)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return " " }
        return result + " "
    }

    private struct Rule {
        let pattern: String
        let replacement: String
    }

    private static let spokenCommandRules: [Rule] = [
        Rule(pattern: #"(?i)\bnew\s+paragraph\b"#, replacement: "\n\n"),
        Rule(pattern: #"(?i)\bnew\s+line\b"#, replacement: "\n"),
        Rule(pattern: #"(?i)\bnewline\b"#, replacement: "\n"),
    ]

    private static func replace(pattern: String, with replacement: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func normaliseSpacing(_ text: String) -> String {
        var result = text

        // No space before closing punctuation / closers.
        result = replace(pattern: #"\s+([,.;:?!…\)\]])"#, with: "$1", in: result)
        result = replace(pattern: #"\s+(\")"#, with: "$1", in: result)
        // No space after opening punctuation.
        result = replace(pattern: #"([\(\[])\s+"#, with: "$1", in: result)
        result = replace(pattern: #"(\")\s+"#, with: "$1", in: result)
        // Single space after sentence/clause punctuation when more text follows on the line.
        result = replace(pattern: #"([,.;:?!…])([^\s\n])"#, with: "$1 $2", in: result)
        // Trim spaces around newlines.
        result = replace(pattern: #"[ \t]*\n[ \t]*"#, with: "\n", in: result)
        // Collapse runs of spaces/tabs (preserve newlines).
        result = replace(pattern: #"[ \t]{2,}"#, with: " ", in: result)
        // Collapse 3+ newlines to a paragraph break.
        result = replace(pattern: #"\n{3,}"#, with: "\n\n", in: result)

        return result
    }
}

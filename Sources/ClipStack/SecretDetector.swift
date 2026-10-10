import Foundation

/// Spots copied text that looks like a password, API key or token, so it isn't kept in the history.
/// Password managers mark their copies; this catches keys copied from a terminal, a web page or a file.
enum SecretDetector {
    private static let patterns: [NSRegularExpression] = [
        "-----BEGIN [A-Z ]*PRIVATE KEY-----",
        // Provider-specific key formats.
        "^sk-[A-Za-z0-9_-]{20,}$",                       // OpenAI, Anthropic and similar
        "^(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}$",      // GitHub tokens
        "^github_pat_[A-Za-z0-9_]{20,}$",
        "^(AKIA|ASIA)[0-9A-Z]{16}$",                     // AWS access key IDs
        "^AIza[0-9A-Za-z_-]{35}$",                       // Google API keys
        "^xox[abposr]-[A-Za-z0-9-]{10,}$",               // Slack tokens
        "^(sk|rk|pk)_(live|test)_[A-Za-z0-9]{16,}$",     // Stripe keys
        "^glpat-[A-Za-z0-9_-]{20,}$",                    // GitLab tokens
        "^eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}$", // JWTs
        // Assignments such as `API_KEY=…` or `password: …`.
        "(?i)\\b(api[_-]?key|secret|token|passw(or)?d|pwd|access[_-]?key|client[_-]?secret)\\b\\s*[:=]\\s*\\S{6,}",
    ].map { try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }

    static func looksSecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= 20_000 else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if patterns.contains(where: { $0.firstMatch(in: trimmed, range: range) != nil }) { return true }
        return looksLikeRandomToken(trimmed)
    }

    /// A single long run of mixed letters and digits with high entropy, like a generated key.
    private static func looksLikeRandomToken(_ text: String) -> Bool {
        guard (24...256).contains(text.count),
              !text.contains(where: \.isWhitespace),
              !text.contains("://"), !text.contains("@"), !text.contains("/"), !text.contains("\\"),
              text.contains(where: \.isNumber),
              text.contains(where: \.isLowercase),
              text.contains(where: \.isUppercase) else { return false }
        var counts: [Character: Int] = [:]
        for character in text { counts[character, default: 0] += 1 }
        let length = Double(text.count)
        let entropy = counts.values.reduce(0.0) { total, count in
            let p = Double(count) / length
            return total - p * log2(p)
        }
        return entropy >= 4.0
    }
}

import Foundation

/// Pure address-bar → navigable URL helpers (no UI / FoundationModels).
public enum AddressResolver: Sendable {
    /// Fast path before CoreAI: home aliases, full URLs, bare domains / localhost.
    public static func heuristicURL(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "about:home" }

        let lower = trimmed.lowercased()
        if lower == "home" || lower == "about:home" || lower == "gama:home" {
            return "about:home"
        }
        if trimmed.contains("://") {
            return trimmed
        }
        if looksLikeHostOrIP(trimmed) {
            return "https://\(trimmed)"
        }
        return nil
    }

    /// Normalize a model reply into a single navigable target, or `nil`.
    public static func sanitizeModelURL(_ raw: String) -> String? {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        if trimmed.isEmpty { return nil }
        if trimmed.lowercased() == "about:home" || trimmed.lowercased() == "gama:home" {
            return "about:home"
        }
        if trimmed.contains("://") { return trimmed }
        if looksLikeHostOrIP(trimmed) {
            return "https://\(trimmed)"
        }
        return nil
    }

    public static func searchURL(for query: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return "https://duckduckgo.com/?q=\(encoded)"
    }

    /// Resolve without CoreAI (heuristics → search fallback).
    public static func resolveOffline(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "about:home" }
        return heuristicURL(for: trimmed) ?? searchURL(for: trimmed)
    }

    private static func looksLikeHostOrIP(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        let hostPart = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? text
        let lower = hostPart.lowercased()
        if lower == "localhost" || lower.hasPrefix("localhost:") {
            return true
        }
        // IPv4 with optional port.
        if hostPart.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?$"#, options: .regularExpression) != nil {
            return true
        }
        // Bare domain (has a dot, no spaces).
        return hostPart.contains(".")
    }
}

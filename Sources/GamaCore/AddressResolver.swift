import Foundation

/// Pure address-bar → navigable URL helpers (no UI / FoundationModels).
public enum AddressResolver: Sendable {
    /// Validate a direct or restored navigation target and normalize home aliases.
    public static func navigableURL(for raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower == "home" || lower == "about:home" || lower == "gama:home" {
            return "about:home"
        }

        let candidate: String
        if raw.contains("://") {
            candidate = raw
        } else {
            guard looksLikeHostOrIP(raw) else { return nil }
            candidate = "https://\(raw)"
        }
        guard let schemeEnd = candidate.range(of: "://")?.upperBound else { return nil }
        let authorityEnd = candidate[schemeEnd...].firstIndex(where: { "/?#".contains($0) }) ?? candidate.endIndex
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !candidate.unicodeScalars.contains(where: forbidden.contains),
              let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              !host.unicodeScalars.contains(where: forbidden.contains),
              url.user == nil, url.password == nil,
              !candidate[schemeEnd..<authorityEnd].contains("@"),
              validPort(in: String(candidate[schemeEnd..<authorityEnd])),
              validIPv4(host) else { return nil }
        return candidate
    }

    /// Fast path before CoreAI: home aliases, full URLs, bare domains / localhost.
    public static func heuristicURL(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "about:home" }

        return navigableURL(for: trimmed)
    }

    /// Normalize a model reply into a single navigable target, or `nil`.
    public static func sanitizeModelURL(_ raw: String) -> String? {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        return navigableURL(for: trimmed)
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

    private static func validPort(in authority: String) -> Bool {
        let hostEnd: String.SubSequence
        if authority.hasPrefix("["), let closing = authority.firstIndex(of: "]") {
            hostEnd = authority[authority.index(after: closing)...]
        } else {
            hostEnd = authority[...]
        }
        guard let colon = hostEnd.firstIndex(of: ":") else { return true }
        let digits = hostEnd[hostEnd.index(after: colon)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let port = Int(digits) else { return false }
        return (0...65535).contains(port)
    }

    private static func validIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return true }
        guard octets.count == 4 else { return false }
        return octets.allSatisfy {
            !$0.isEmpty && ($0.count == 1 || $0.first != "0") &&
                $0.allSatisfy(\.isASCII) && Int($0).map { (0...255).contains($0) } == true
        }
    }
}

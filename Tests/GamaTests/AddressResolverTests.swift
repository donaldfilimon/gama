import Foundation
import GamaCore
import Testing

@Test func heuristicHomeAliases() {
    #expect(AddressResolver.heuristicURL(for: "home") == "about:home")
    #expect(AddressResolver.heuristicURL(for: "about:home") == "about:home")
    #expect(AddressResolver.heuristicURL(for: "gama:home") == "about:home")
    #expect(AddressResolver.heuristicURL(for: "  ") == "about:home")
}

@Test func heuristicBareDomainAndLocalhost() {
    #expect(AddressResolver.heuristicURL(for: "apple.com") == "https://apple.com")
    #expect(AddressResolver.heuristicURL(for: "www.swift.org/docs") == "https://www.swift.org/docs")
    #expect(AddressResolver.heuristicURL(for: "localhost") == "https://localhost")
    #expect(AddressResolver.heuristicURL(for: "127.0.0.1:8080") == "https://127.0.0.1:8080")
}

@Test func heuristicLeavesFullURLAndRejectsQueries() {
    #expect(AddressResolver.heuristicURL(for: "https://example.com/a") == "https://example.com/a")
    #expect(AddressResolver.heuristicURL(for: "swift concurrency docs") == nil)
}

@Test func sanitizeModelURLStripsQuotesAndNoise() {
    #expect(AddressResolver.sanitizeModelURL("\"https://swift.org\"") == "https://swift.org")
    #expect(AddressResolver.sanitizeModelURL("about:home\nextra") == "about:home")
    #expect(AddressResolver.sanitizeModelURL("not a url") == nil)
}

@Test func resolveOfflineFallsBackToSearch() {
    let url = AddressResolver.resolveOffline("swift structured concurrency")
    #expect(url.hasPrefix("https://duckduckgo.com/?q="))
    #expect(url.contains("swift"))
}

// MARK: - Scheme allowlist

@Test func heuristicRejectsSchemesOutsideTheAllowlist() {
    // `allowedSchemes` exists to keep file:, javascript: and friends out of the
    // web view. Nothing tested it, so deleting the allowlist passed the suite.
    #expect(AddressResolver.heuristicURL(for: "file:///etc/passwd") == nil)
    #expect(AddressResolver.heuristicURL(for: "ftp://example.com/x") == nil)
    #expect(AddressResolver.heuristicURL(for: "javascript://example.com/%0aalert(1)") == nil)
    #expect(AddressResolver.heuristicURL(for: "data://text/html,x") == nil)
}

@Test func heuristicKeepsTheAllowedSchemesAndIgnoresSchemeCase() {
    #expect(AddressResolver.heuristicURL(for: "http://example.com") == "http://example.com")
    #expect(AddressResolver.heuristicURL(for: "https://example.com") == "https://example.com")
    // The scheme comparison lowercases, so a shouted URL is still allowed and
    // is handed back unchanged rather than normalized.
    #expect(AddressResolver.heuristicURL(for: "HTTPS://EXAMPLE.COM") == "HTTPS://EXAMPLE.COM")
}

@Test func modelOutputCannotSmuggleADangerousScheme() {
    // sanitizeModelURL is the highest-risk entry point: the string comes from a
    // language model, and it strips quotes and backticks before deciding. Every
    // rejection below had no coverage.
    #expect(AddressResolver.sanitizeModelURL("file:///etc/passwd") == nil)
    #expect(AddressResolver.sanitizeModelURL("\"file:///etc/passwd\"") == nil)
    #expect(AddressResolver.sanitizeModelURL("`javascript://x.com/%0aalert(1)`") == nil)
    #expect(AddressResolver.sanitizeModelURL("ftp://example.com") == nil)
    // A legitimate reply still survives the same path.
    #expect(AddressResolver.sanitizeModelURL("'https://swift.org'") == "https://swift.org")
}

// MARK: - Search query encoding

@Test func searchQueryEncodesTheCharactersThatWouldSplitTheQueryString() {
    // `+`, `&` and `=` are removed from the allowed set on purpose: left raw
    // they would add or overwrite DuckDuckGo parameters instead of searching
    // for the text. Nothing asserted that, so the removal could be dropped.
    let amp = AddressResolver.searchURL(for: "a&b=c")
    #expect(!amp.dropFirst("https://duckduckgo.com/?q=".count).contains("&"))
    #expect(!amp.dropFirst("https://duckduckgo.com/?q=".count).contains("="))

    let plus = AddressResolver.searchURL(for: "c++ lambdas")
    #expect(!plus.dropFirst("https://duckduckgo.com/?q=".count).contains("+"))

    // `#` would truncate the query into a fragment.
    let hash = AddressResolver.searchURL(for: "swift #available")
    #expect(!hash.contains("#"))

    #expect(AddressResolver.searchURL(for: "swift").hasPrefix("https://duckduckgo.com/?q="))
}

@Test func resolveOfflineRoutesEachInputToTheRightBranch() {
    #expect(AddressResolver.resolveOffline("") == "about:home")
    #expect(AddressResolver.resolveOffline("   ") == "about:home")
    #expect(AddressResolver.resolveOffline("apple.com") == "https://apple.com")
    #expect(AddressResolver.resolveOffline("https://swift.org") == "https://swift.org")
    // A rejected scheme must not fall through to navigation; it becomes a search.
    #expect(AddressResolver.resolveOffline("file:///etc/passwd").hasPrefix("https://duckduckgo.com/?q="))
}

@Test func navigableURLPreservesValidTargets() {
    #expect(AddressResolver.navigableURL(for: "gama:home") == "about:home")
    #expect(AddressResolver.navigableURL(for: "HTTPS://EXAMPLE.COM/a?b=c#part") == "HTTPS://EXAMPLE.COM/a?b=c#part")
    #expect(AddressResolver.navigableURL(for: "http://[::1]:8080/a") == "http://[::1]:8080/a")
    #expect(AddressResolver.navigableURL(for: "example.com/a?b=c#part") == "https://example.com/a?b=c#part")
    #expect(AddressResolver.navigableURL(for: "127.0.0.1:65535") == "https://127.0.0.1:65535")
}

@Test func directTargetsMustHaveSafeAuthorities() {
    for input in [
        "https:///path", "https://?q=one", "http://#fragment",
        "https://user:pass@example.com", "https://user@example.com",
        "https://example.com:", "https://example.com:abc", "https://example.com:65536",
        "example.com:65536", "256.1.1.1", "https://1.2.3.999", "001.2.3.4", "1.2.3",
        "https://example.com/a b", "example.com\t/path", "https://example.com/\nnext",
        " https://example.com", "https://example.com ",
    ] {
        #expect(AddressResolver.navigableURL(for: input) == nil)
    }
    #expect(AddressResolver.heuristicURL(for: "https://example.com/a b") == nil)
    #expect(AddressResolver.heuristicURL(for: "1.2.3") == nil)
}

@Test func modelTargetsUseTheSameValidation() {
    #expect(AddressResolver.sanitizeModelURL("'https://example.com/a?b=c#part'") == "https://example.com/a?b=c#part")
    for input in [
        "https:///missing", "https://user@example.com", "example.com:99999",
        "http://999.1.1.1", "https://example.com/a b", "ftp://example.com",
        "file:///etc/passwd", "javascript://example.com/alert(1)",
    ] {
        #expect(AddressResolver.sanitizeModelURL(input) == nil)
    }
}

@Test func rejectedDirectNavigationBecomesOfflineSearch() {
    let rejected = "https://user@example.com/private"
    #expect(AddressResolver.heuristicURL(for: rejected) == nil)
    #expect(AddressResolver.resolveOffline(rejected) == AddressResolver.searchURL(for: rejected))
}

@Test func percentEncodedWhitespaceCannotEnterParsedHost() {
    let rejected = "https://example.com%20.evil.com"
    #expect(AddressResolver.navigableURL(for: rejected) == nil)
    #expect(AddressResolver.heuristicURL(for: rejected) == nil)
    #expect(AddressResolver.sanitizeModelURL(rejected) == nil)
    #expect(AddressResolver.resolveOffline(rejected) == AddressResolver.searchURL(for: rejected))
    #expect(AddressResolver.navigableURL(for: "https://example.com/a%20b") == "https://example.com/a%20b")
}

@Test func numericHostsRejectEmptyOctetsAcrossEntryPoints() {
    for host in ["256.1.1.1.", "1..2.3", ".1.2.3", "1.2.3.", "999..1.1", "127.0.0.1."] {
        for input in [host, "https://\(host)"] {
            #expect(AddressResolver.navigableURL(for: input) == nil)
            #expect(AddressResolver.heuristicURL(for: input) == nil)
            #expect(AddressResolver.sanitizeModelURL("'\(input)'") == nil)
            #expect(AddressResolver.resolveOffline(input) == AddressResolver.searchURL(for: input))
        }
    }
}

@Test func numericHostValidationPreservesValidAddressesAndDomains() {
    for host in ["127.0.0.1", "example.com", "123.example.com", "example.com."] {
        let target = "https://\(host)"
        for input in [host, target] {
            #expect(AddressResolver.navigableURL(for: input) == target)
            #expect(AddressResolver.heuristicURL(for: input) == target)
            #expect(AddressResolver.sanitizeModelURL("'\(input)'") == target)
            #expect(AddressResolver.resolveOffline(input) == target)
        }
    }
    let ipv6 = "http://[::1]:8080/a"
    #expect(AddressResolver.navigableURL(for: ipv6) == ipv6)
    #expect(AddressResolver.heuristicURL(for: ipv6) == ipv6)
    #expect(AddressResolver.sanitizeModelURL(ipv6) == ipv6)
    #expect(AddressResolver.resolveOffline(ipv6) == ipv6)
}

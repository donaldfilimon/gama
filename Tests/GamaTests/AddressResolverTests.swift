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

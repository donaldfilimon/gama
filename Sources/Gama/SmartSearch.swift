import Foundation
import GamaCore
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// CoreAI / Foundation Models façade for routing, suggestions, and page insights.
@MainActor
@Observable
final class SmartSearchService {
    static let shared = SmartSearchService()

    private(set) var isAvailable = false
    private(set) var availabilityMessage = "Checking…"
    private(set) var lastRationale: String = ""
    private(set) var suggestions: [String] = []
    private(set) var pageInsight: String = ""
    private(set) var pageTopics: [String] = []
    private(set) var isSuggesting = false
    private(set) var isSummarizing = false

    #if canImport(FoundationModels)
    private var routerSession: LanguageModelSession?
    private var suggestSession: LanguageModelSession?
    private var insightSession: LanguageModelSession?
    private var suggestTask: Task<Void, Never>?
    #endif

    private init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel(useCase: .general, guardrails: .default)
        switch model.availability {
        case .available:
            isAvailable = true
            availabilityMessage = "CoreAI ready"
            routerSession = LanguageModelSession(
                model: model,
                instructions: Instructions(
                    """
                    You are Gama's address-bar router. Produce a structured AddressRoute.
                    Rules:
                    - home / about:home / gama:home → destination about:home, kind home
                    - Existing URLs or domains → normalize https:// when needed, kind url
                    - Natural-language questions → DuckDuckGo URL https://duckduckgo.com/?q=<encoded>, kind search
                    - Prefer apple.com, swift.org, developer.apple.com, doc.qt.io when clearly intended
                    - destination must be only the URL or about:home
                    """
                )
            )
            suggestSession = LanguageModelSession(
                model: model,
                instructions: Instructions(
                    """
                    You complete Gama's address bar. Return AddressSuggestions with up to 5 items.
                    Prefer concrete URLs or short search phrases. No commentary.
                    """
                )
            )
            let tagging = SystemLanguageModel(useCase: .contentTagging, guardrails: .default)
            insightSession = LanguageModelSession(
                model: tagging.availability == .available ? tagging : model,
                instructions: Instructions(
                    """
                    Summarize a browser tab for a power user. Return PageInsight with a tight summary,
                    topical tags, and one follow-up search query.
                    """
                )
            )
            routerSession?.prewarm()
            suggestSession?.prewarm()
        case .unavailable(let reason):
            isAvailable = false
            routerSession = nil
            suggestSession = nil
            insightSession = nil
            switch reason {
            case .deviceNotEligible:
                availabilityMessage = "Device not eligible"
            case .appleIntelligenceNotEnabled:
                availabilityMessage = "Enable Apple Intelligence"
            case .modelNotReady:
                availabilityMessage = "Model warming up"
            @unknown default:
                availabilityMessage = "CoreAI unavailable"
            }
        }
        #else
        isAvailable = false
        availabilityMessage = "FoundationModels missing"
        #endif
    }

    /// Resolve free-form address-bar text into a URL string.
    func resolve(_ query: String) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastRationale = "Empty → home"
            return "about:home"
        }

        if let heuristic = AddressResolver.heuristicURL(for: trimmed) {
            lastRationale = "Heuristic"
            suggestions = []
            return heuristic
        }

        #if canImport(FoundationModels)
        guard isAvailable, let routerSession else {
            lastRationale = "Offline search"
            return AddressResolver.searchURL(for: trimmed)
        }
        do {
            let response = try await routerSession.respond(
                to: trimmed,
                generating: AddressRoute.self
            )
            let route = response.content
            lastRationale = "\(route.kind): \(route.rationale)"
            if let cleaned = AddressResolver.sanitizeModelURL(route.destination) {
                return cleaned
            }
            if route.kind.lowercased() == "home" {
                return "about:home"
            }
            if route.kind.lowercased() == "search" {
                return AddressResolver.searchURL(for: trimmed)
            }
        } catch {
            lastRationale = "Model error → search"
        }
        #endif
        return AddressResolver.searchURL(for: trimmed)
    }

    /// Debounced CoreAI suggestions while typing in the address field.
    func scheduleSuggestions(for partial: String) {
        #if canImport(FoundationModels)
        suggestTask?.cancel()
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, trimmed.count >= 3, AddressResolver.heuristicURL(for: trimmed) == nil else {
            suggestions = []
            isSuggesting = false
            return
        }
        suggestTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await refreshSuggestions(for: trimmed)
        }
        #else
        suggestions = []
        #endif
    }

    func clearSuggestions() {
        #if canImport(FoundationModels)
        suggestTask?.cancel()
        #endif
        suggestions = []
        isSuggesting = false
    }

    func summarizePage(title: String, url: String) async {
        pageInsight = ""
        pageTopics = []
        #if canImport(FoundationModels)
        guard isAvailable, let insightSession else {
            pageInsight = "CoreAI unavailable for page insight."
            return
        }
        isSummarizing = true
        defer { isSummarizing = false }
        let prompt = """
        Title: \(title)
        URL: \(url)
        Provide a concise PageInsight for this tab.
        """
        do {
            let response = try await insightSession.respond(
                to: prompt,
                generating: PageInsight.self
            )
            let insight = response.content
            pageInsight = insight.summary
            pageTopics = insight.topics
            if !insight.followUpQuery.isEmpty {
                suggestions = [insight.followUpQuery]
            }
        } catch {
            pageInsight = "Could not summarize: \(error.localizedDescription)"
        }
        #else
        pageInsight = "FoundationModels missing"
        #endif
    }

    #if canImport(FoundationModels)
    private func refreshSuggestions(for partial: String) async {
        guard let suggestSession else { return }
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let response = try await suggestSession.respond(
                to: "Partial address-bar input: \(partial)",
                generating: AddressSuggestions.self
            )
            suggestions = Array(response.content.suggestions.prefix(5))
        } catch {
            suggestions = []
        }
    }
    #endif
}

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Guided address-bar route from Foundation Models.
@Generable(description: "A single navigable destination for the Gama address bar.")
struct AddressRoute {
    @Guide(description: "Exact URL or about:home — no markdown or commentary.")
    var destination: String

    @Guide(description: "One of: home, url, search")
    var kind: String

    @Guide(description: "Short reason for the route choice.")
    var rationale: String
}

@Generable(description: "Address-bar autocomplete suggestions.")
struct AddressSuggestions {
    @Guide(description: "Up to 5 short navigable suggestions (URLs or search phrases).")
    var suggestions: [String]
}

@Generable(description: "On-device insight about the active browser tab.")
struct PageInsight {
    @Guide(description: "One or two sentence summary of the page.")
    var summary: String

    @Guide(description: "3-5 topical tags.")
    var topics: [String]

    @Guide(description: "A follow-up search query the user might want.")
    var followUpQuery: String
}
#endif

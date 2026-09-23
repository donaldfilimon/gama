import Foundation
import GamaAuthoring
import GamaUSD
import Testing

/// Pins the writer's exact output and the reader's tolerance for text another
/// USD tool reformatted.
///
/// Regenerate after a deliberate format change (then re-run `usdcat` on the
/// golden to refresh the reformatted fixture, and check both with
/// `usdchecker`):
///
///     GAMA_UPDATE_GOLDEN=1 swift test --filter FixtureTests
@Suite("USDA fixtures")
struct FixtureTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    func fixture(_ name: String) throws -> String {
        try String(contentsOf: Self.fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    /// `tools/check.sh` runs `usdchecker` over every golden here, so these
    /// scenes are also the gate's proof that the writer emits valid USD.
    static let goldens = ["everything.usda", "nesting.usda", "awkward-names.usda", "graphs.usda"]

    static func scene(for golden: String) throws -> SceneDocument {
        switch golden {
        case "nesting.usda": try Scenes.nesting()
        case "awkward-names.usda": try Scenes.awkwardNames()
        case "graphs.usda": try Scenes.graphs()
        default: try Scenes.everything()
        }
    }

    @Test(arguments: goldens)
    func writerMatchesTheGoldenFile(_ name: String) throws {
        let text = usdaString(from: try Self.scene(for: name))
        if ProcessInfo.processInfo.environment["GAMA_UPDATE_GOLDEN"] == "1" {
            try text.write(to: Self.fixtures.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        #expect(text == (try fixture(name)), "\(name)")
    }

    /// `everything.usdcat.usda` is `usdcat everything.usda` verbatim: attributes
    /// reordered, metadata reflowed, and floats shortened.
    @Test func readerAcceptsUsdcatReformatting() throws {
        let reformatted = try fixture("everything.usdcat.usda")
        #expect(reformatted != (try fixture("everything.usda")))
        #expect(try sceneDocument(fromUSDA: reformatted) == Scenes.everything())
        // The same for the graph library (`usdcat graphs.usda`).
        let graphs = try fixture("graphs.usdcat.usda")
        #expect(graphs != (try fixture("graphs.usda")))
        #expect(try sceneDocument(fromUSDA: graphs) == Scenes.graphs())
    }
}

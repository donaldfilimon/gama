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

    @Test func writerMatchesTheGoldenFile() throws {
        let text = usdaString(from: try Scenes.everything())
        if ProcessInfo.processInfo.environment["GAMA_UPDATE_GOLDEN"] == "1" {
            try text.write(to: Self.fixtures.appendingPathComponent("everything.usda"), atomically: true, encoding: .utf8)
        }
        #expect(text == (try fixture("everything.usda")))
    }

    /// `everything.usdcat.usda` is `usdcat everything.usda` verbatim: attributes
    /// reordered, metadata reflowed, and floats shortened.
    @Test func readerAcceptsUsdcatReformatting() throws {
        let reformatted = try fixture("everything.usdcat.usda")
        #expect(reformatted != (try fixture("everything.usda")))
        #expect(try sceneDocument(fromUSDA: reformatted) == Scenes.everything())
    }
}

import Testing
import ArgumentParser
import GamaCore
@testable import gama

@Suite
struct CLITests {
    @Test func versionIs010() {
        #expect(gama.configuration.version == "0.1.0")
    }

    @Test func demoIsASubcommand() {
        #expect(gama.configuration.subcommands.contains { $0 == Demo.self })
    }

    @Test func demoTreeIDsAreUnique() {
        let ids = DemoApp().collectIDs(DemoApp().body())
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(NodeID("name")))
        #expect(ids.contains(NodeID("quit")))
    }
}

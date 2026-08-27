import GamaCore
import GamaEmbed
import Testing

private struct EmbedProbeApp: App {
    var scenes: some Scene {
        Window("Embedded", id: "main", role: .primary) { Text("embedded") }
    }
}

@Suite("C embedding context")
struct EmbedTests {
    @Test("contexts own independent frames and reject null handles")
    func contextLifecycle() throws {
        let first = try GamaEmbed.makeContext(app: EmbedProbeApp(), columns: 12, rows: 2)
        let second = try GamaEmbed.makeContext(app: EmbedProbeApp(), columns: 20, rows: 3)
        defer {
            gama_embed_v1_context_destroy(first)
            gama_embed_v1_context_destroy(second)
        }

        #expect(gama_embed_v1_needs_frame(first) == 1)
        #expect(gama_embed_v1_needs_frame(second) == 1)
        var firstLength: Int32 = 0
        #expect(gama_embed_v1_frame(first, &firstLength) != nil)
        #expect(firstLength > 20)
        #expect(gama_embed_v1_needs_frame(first) == 0)
        #expect(gama_embed_v1_needs_frame(second) == 1)
        #expect(gama_embed_v1_resize(nil, 1, 1) == -1)
        #expect(gama_embed_v1_key(first, 999, 0, 0, 0) == -2)
    }
}

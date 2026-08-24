import GamaCore
import GamaMacros
import Testing

@Component
private struct MacroBadge {
    let label: String
    @Reactive var count: Int = 0

    var body: some View {
        Text("\(label): \(count)").foregroundColor(#rgb("F80"))
    }
}

@Suite("Macro public surface")
struct MacroUsageTests {
    @Test("component, reactive, and RGB macros compile into core views")
    func macroSurface() {
        let badge = MacroBadge(label: "count")
        badge.count = 3
        let rendered = badge.render(in: BuildContext())
        guard case .styled(let style, let child) = rendered,
              case .text(let text, _) = child else {
            Issue.record("expected styled text render node")
            return
        }
        #expect(text == "count: 3")
        #expect(style.foreground == Color(r: 255, g: 136, b: 0))
    }
}

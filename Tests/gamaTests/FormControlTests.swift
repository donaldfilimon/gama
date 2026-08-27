import GamaCore
import Testing

private struct FormApp: App {
    let text = Signal("")
    let enabled = Signal(false)

    init() {}

    var scenes: some Scene {
        Window("Forms", id: "main", role: .primary) {
            VStack {
                TextField("Name", text: text.binding())
                Toggle("Enabled", isOn: enabled.binding())
                ProgressView(value: 1, total: 4, label: "Load")
            }
        }
    }
}

@Suite("Form controls and identity")
struct FormControlTests {
    @Test("progress renders a sub-cell fraction with a partial boundary glyph")
    func progressRounding() {
        let rendered = ProgressView(value: 1, total: 8, label: "Load")
            .render(in: BuildContext())

        guard case .text(let text, _) = rendered else {
            Issue.record("ProgressView did not render text")
            return
        }
        // 1/8 = 2.5 of 20 cells: two full cells plus a half-block
        // boundary glyph, not three whole cells rounded away from zero.
        #expect(text == "Load [██▌░░░░░░░░░░░░░░░░░] 13%")
    }

    @Test("focused text input edits and toggle activates")
    func editingAndToggle() throws {
        let app = FormApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.character("A")))
        host.handle(.key(.character("b")))
        host.handle(.key(.backspace))
        #expect(app.text.get() == "A")

        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.tab))
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.enter))
        #expect(app.enabled.get())
    }

    @Test("duplicate explicit identities are reported once")
    func duplicateIdentity() throws {
        struct DuplicateApp: App {
            init() {}
            var scenes: some Scene {
                Window("Duplicate", id: "main", role: .primary) {
                    VStack {
                        IdentifiedForEach([1, 2], id: { _ in NodeID(raw: 7) }) { value in
                            Button("\(value)") {}
                        }
                    }
                }
            }
        }

        var host = try FrameHost(app: DuplicateApp())
        _ = host.pump(size: Size(width: 20, height: 4))
        #expect(host.duplicateIDs == [NodeID(raw: 7)])
    }
}

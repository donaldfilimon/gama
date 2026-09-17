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

    @Test("a space typed into a focused text field becomes content, not activation")
    func spaceIsTextNotActivation() throws {
        let app = FormApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        for character in "hi there" {
            host.handle(.key(.character(character)))
        }
        #expect(app.text.get() == "hi there")
    }

    @Test("space still activates a focused button-backed control")
    func spaceStillActivatesToggle() throws {
        let app = FormApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.tab))
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.character(" ")))
        #expect(app.enabled.get())
    }

    @Test("enter on a focused text field still falls through to activation")
    func enterFallsBackToActivation() throws {
        let app = FormApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.character("A")))
        _ = host.pump(size: Size(width: 40, height: 8))

        host.handle(.key(.enter))
        // The field's handler declines `.enter`, so it must reach the
        // activation path: the text is untouched and the host is dirty.
        // The generic key route sets dirty only for a handled key, so this
        // flag is what distinguishes activation from a swallowed keystroke.
        let dirtyAfterEnter = host.needsFrame
        #expect(app.text.get() == "A")
        #expect(dirtyAfterEnter)
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

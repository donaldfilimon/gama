import GamaCore
import Testing

private struct FormApp: App {
    let text = Signal("")
    let enabled = Signal(false)

    init() {}

    var content: some View {
        VStack {
            TextField("Name", text: text.binding())
            Toggle("Enabled", isOn: enabled.binding())
            ProgressView(value: 1, total: 4, label: "Load")
        }
    }
}

@Suite("Form controls and identity")
struct FormControlTests {
    @Test("focused text input edits and toggle activates")
    func editingAndToggle() {
        var host = FrameHost(app: FormApp())
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.character("A")))
        host.handle(.key(.character("b")))
        host.handle(.key(.backspace))
        #expect(host.app.text.get() == "A")

        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.tab))
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.enter))
        #expect(host.app.enabled.get())
    }

    @Test("duplicate explicit identities are reported once")
    func duplicateIdentity() {
        struct DuplicateApp: App {
            init() {}
            var content: some View {
                VStack {
                    IdentifiedForEach([1, 2], id: { _ in NodeID(raw: 7) }) { value in
                        Button("\(value)") {}
                    }
                }
            }
        }

        var host = FrameHost(app: DuplicateApp())
        _ = host.pump(size: Size(width: 20, height: 4))
        #expect(host.duplicateIDs == [NodeID(raw: 7)])
    }
}

//  ActionIdentityTests.swift — one action identity, three dispatch paths.

import GamaCore
import Testing

private let addAction = ActionID("counter.add")

private struct AddApp: App {
    let count = Signal(0)
    let enabled = Signal(true)

    init() {}

    var scenes: some Scene {
        Window("Add", id: "main", role: .primary) {
            Button("Add") { count.set(count.get() + 1) }
                .actionIdentity(addAction, shortcut: .ctrl("a"))
                .disabled(!enabled.get())
        }
    }
}

private struct WidthApp: App {
    let count = Signal(0)

    init() {}

    var scenes: some Scene {
        Window("Width", id: "main", role: .primary) {
            HStack {
                Text("side").frame(width: 8)
                Text("body").frame(minWidth: 1, maxWidth: .max)
                Button("Add") { count.set(count.get() + 1) }
                    .actionIdentity(addAction, shortcut: .ctrl("a"))
            }
        }
    }
}

private struct PairApp: App {
    let first = Signal(0)
    let second = Signal(0)

    init() {}

    var scenes: some Scene {
        Window("Pair", id: "main", role: .primary) {
            VStack {
                Button("First") { first.set(first.get() + 1) }
                    .actionIdentity(ActionID("first"), shortcut: .ctrl("c"))
                Button("Second") { second.set(second.get() + 1) }
                    .actionIdentity(ActionID("second"), shortcut: .ctrl("b"))
            }
        }
    }
}

private struct FieldApp: App {
    let text = Signal("")
    let count = Signal(0)

    init() {}

    var scenes: some Scene {
        Window("Field", id: "main", role: .primary) {
            VStack {
                TextField("Name", text: text.binding())
                Button("Add") { count.set(count.get() + 1) }
                    .actionIdentity(ActionID("add"), shortcut: .character("x"))
            }
        }
    }
}

private struct OverlapApp: App {
    let early = Signal(0)
    let late = Signal(0)

    init() {}

    var scenes: some Scene {
        Window("Overlap", id: "main", role: .primary) {
            VStack {
                Button("Early") { early.set(early.get() + 1) }
                    .actionIdentity(ActionID("shared"), shortcut: .ctrl("a"))
                Button("Late") { late.set(late.get() + 1) }
                    .actionIdentity(ActionID("shared"), shortcut: .ctrl("a"))
            }
        }
    }
}

private struct DistinctShortcutApp: App {
    let early = Signal(0)
    let late = Signal(0)

    init() {}

    var scenes: some Scene {
        Window("Distinct", id: "main", role: .primary) {
            VStack {
                Button("Early") { early.set(early.get() + 1) }
                    .actionIdentity(ActionID("early"), shortcut: .ctrl("a"))
                Button("Late") { late.set(late.get() + 1) }
                    .actionIdentity(ActionID("late"), shortcut: .ctrl("a"))
            }
        }
    }
}

private struct NestedIdentityApp: App {
    let count = Signal(0)

    init() {}

    var scenes: some Scene {
        Window("Nested", id: "main", role: .primary) {
            Button("Add") { count.set(count.get() + 1) }
                .actionIdentity(ActionID("inner"), shortcut: .ctrl("i"))
                .actionIdentity(ActionID("outer"), shortcut: .ctrl("o"))
        }
    }
}

private func flexWidths(_ node: LaidOutNode) -> [Int] {
    var found: [Int] = []
    if case .flexFrame = node.node {
        found.append(node.frame.size.width)
    }
    for child in node.children {
        found.append(contentsOf: flexWidths(child))
    }
    return found
}

@Suite("Action identity")
struct ActionIdentityTests {
    @Test("activation, shortcut, and direct dispatch share one effect")
    func activationShortcutAndDispatchShareOneEffect() throws {
        let app = AddApp()
        var host = try FrameHost(app: app)
        host.perform(addAction)
        #expect(app.count.get() == 0)

        _ = host.pump(size: Size(width: 40, height: 6))
        host.handle(.key(.enter))
        #expect(app.count.get() == 1)
        host.handle(.key(.character(" ")))
        #expect(app.count.get() == 2)
        host.handle(.key(.ctrl("a")))
        #expect(app.count.get() == 3)
        host.perform(addAction)
        #expect(app.count.get() == 4)
    }

    @Test("a disabled action does not run from any path")
    func disabledActionDoesNotRun() throws {
        let app = AddApp()
        app.enabled.set(false)
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 6))

        host.handle(.key(.enter))
        host.handle(.key(.character(" ")))
        host.handle(.key(.ctrl("a")))
        host.perform(addAction)

        #expect(app.count.get() == 0)
        let dirty = host.needsFrame
        #expect(!dirty)
    }

    @Test("two column widths lay out differently and the action still fires")
    func layoutDiffersByWidthAndActionDoesNot() throws {
        let app = WidthApp()
        var host = try FrameHost(app: app)
        let narrow = host.pump(size: Size(width: 40, height: 6))
        host.perform(addAction)
        #expect(app.count.get() == 1)

        let wide = host.pump(size: Size(width: 120, height: 6))
        host.perform(addAction)
        #expect(app.count.get() == 2)

        let narrowFlex = flexWidths(narrow)
        let wideFlex = flexWidths(wide)
        #expect(!narrowFlex.isEmpty)
        #expect(wideFlex.count == narrowFlex.count)
        #expect(wideFlex.max()! > narrowFlex.max()!)
        #expect(narrow.frame.size.width == 40)
        #expect(wide.frame.size.width == 120)
    }

    @Test("quit and tab still win over a declared shortcut")
    func quitAndTabStillWinOverShortcuts() throws {
        let app = PairApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))

        host.handle(.key(.enter))
        #expect(app.first.get() == 1)
        #expect(app.second.get() == 0)

        host.handle(.key(.tab))
        host.handle(.key(.enter))
        #expect(app.second.get() == 1)

        host.handle(.key(.backTab))
        host.handle(.key(.enter))
        #expect(app.first.get() == 2)

        host.handle(.key(.ctrl("b")))
        #expect(app.second.get() == 2)

        host.handle(.key(.ctrl("c")))
        let quit = host.wantsQuit
        #expect(quit)
        #expect(app.first.get() == 2)
        #expect(app.second.get() == 2)

        host.perform(ActionID("first"))
        #expect(app.first.get() == 3)
    }

    @Test("a focused text field consumes a character shortcut")
    func textFieldConsumesCharacterShortcut() throws {
        let app = FieldApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))

        host.handle(.key(.character("x")))
        #expect(app.text.get() == "x")
        #expect(app.count.get() == 0)

        host.handle(.key(.tab))
        host.handle(.key(.character("x")))
        #expect(app.text.get() == "x")
        #expect(app.count.get() == 1)
    }

    @Test("the later control wins a shared identity and shortcut")
    func laterRegistrationWins() throws {
        let app = OverlapApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))

        host.handle(.key(.enter))
        #expect(app.early.get() == 1)
        #expect(app.late.get() == 0)

        host.handle(.key(.ctrl("a")))
        #expect(app.early.get() == 1)
        #expect(app.late.get() == 1)

        host.perform(ActionID("shared"))
        #expect(app.early.get() == 1)
        #expect(app.late.get() == 2)
    }

    @Test("a shared shortcut follows the later identity and the earlier identity remains")
    func distinctIdentitySharedShortcut() throws {
        let app = DistinctShortcutApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))

        host.handle(.key(.enter))
        #expect(app.early.get() == 1)
        #expect(app.late.get() == 0)

        host.handle(.key(.ctrl("a")))
        #expect(app.early.get() == 1)
        #expect(app.late.get() == 1)

        host.perform(ActionID("early"))
        #expect(app.early.get() == 2)
        #expect(app.late.get() == 1)

        host.perform(ActionID("late"))
        #expect(app.early.get() == 2)
        #expect(app.late.get() == 2)
    }

    @Test("the modifier closer to the control replaces an outer one")
    func closerModifierReplacesAncestor() throws {
        let app = NestedIdentityApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 6))

        host.perform(ActionID("outer"))
        #expect(app.count.get() == 0)

        host.handle(.key(.ctrl("o")))
        #expect(app.count.get() == 0)

        host.perform(ActionID("inner"))
        #expect(app.count.get() == 1)

        host.handle(.key(.ctrl("i")))
        #expect(app.count.get() == 2)
    }
}

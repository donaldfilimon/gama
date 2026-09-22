//  TextFieldCursorTests.swift — cursor position and selection model for
//  TextField: pure `TextEditing` operations, then integration through
//  FrameHost proving cursor state survives rebuild and arrow-key dispatch
//  still falls through to spatial focus navigation everywhere else.

import Testing

@testable import GamaCore

@Suite("TextEditing pure functions")
struct TextEditingTests {
    @Test("insert at a mid-string offset splices and advances the cursor by one")
    func insertMidString() {
        let selection = Selection(anchor: 1, head: 1)
        let (value, result) = TextEditing.insert("X", into: "ac", at: selection)
        #expect(value == "aXc")
        #expect(result == Selection(anchor: 2, head: 2))
    }

    @Test("insert over a non-collapsed selection replaces the range and collapses")
    func insertReplacesSelection() {
        let selection = Selection(anchor: 0, head: 2)
        let (value, result) = TextEditing.insert("X", into: "abc", at: selection)
        #expect(value == "Xc")
        #expect(result == Selection(anchor: 1, head: 1))
    }

    @Test("deleteBackward at the start of the field declines")
    func deleteBackwardAtStartDeclines() {
        let selection = Selection(anchor: 0, head: 0)
        #expect(TextEditing.deleteBackward("abc", at: selection) == nil)
    }

    @Test("deleteForward at the end of the field declines")
    func deleteForwardAtEndDeclines() {
        let selection = Selection(anchor: 3, head: 3)
        #expect(TextEditing.deleteForward("abc", at: selection) == nil)
    }

    @Test("deleteBackward never splits a combining grapheme cluster")
    func deleteBackwardKeepsClusterAtomic() {
        let value = "e\u{301}bc"
        let selection = Selection(anchor: 1, head: 1)
        let result = TextEditing.deleteBackward(value, at: selection)
        #expect(result?.0 == "bc")
        #expect(result?.1 == Selection(anchor: 0, head: 0))
    }

    @Test("moveLeft and moveRight are no-ops at the boundaries")
    func moveAtBoundaries() {
        let start = Selection(anchor: 0, head: 0)
        #expect(TextEditing.moveLeft("abc", from: start) == start)
        let end = Selection(anchor: 3, head: 3)
        #expect(TextEditing.moveRight("abc", from: end) == end)
    }
}

private struct CursorFieldApp: App {
    let text = Signal("")
    init() {}

    var scenes: some Scene {
        Window("Cursor", id: "main", role: .primary) {
            TextField("Name", text: text.binding())
        }
    }
}

private struct CursorNavApp: App {
    let text = Signal("")
    let counter = Signal(0)
    init() {}

    var scenes: some Scene {
        Window("Nav", id: "main", role: .primary) {
            VStack(spacing: 1) {
                TextField("Name", text: text.binding())
                Button("Go") { counter.update { $0 += 1 } }
            }
        }
    }
}

private struct HorizontalNavApp: App {
    let left = Signal(0)
    let right = Signal(0)
    init() {}

    var scenes: some Scene {
        Window("HNav", id: "main", role: .primary) {
            HStack(spacing: 1) {
                Button("Left") { left.update { $0 += 1 } }
                Button("Right") { right.update { $0 += 1 } }
            }
        }
    }
}

@Suite("TextField cursor and selection")
struct TextFieldCursorTests {
    @Test("cursor position survives a rebuild between keystrokes")
    func cursorSurvivesRebuild() throws {
        let app = CursorFieldApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        for character in "abc" { host.handle(.key(.character(character))) }
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.home))
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.character("X")))
        #expect(app.text.get() == "Xabc")
    }

    @Test("insert lands at a mid-field cursor, not the end")
    func insertAtMidFieldCursor() throws {
        let app = CursorFieldApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        for character in "abc" { host.handle(.key(.character(character))) }
        host.handle(.key(.left))
        host.handle(.key(.left))
        host.handle(.key(.character("X")))
        #expect(app.text.get() == "aXbc")
    }

    @Test("backspace removes the character before the cursor, not the last character")
    func backspaceAtCursor() throws {
        let app = CursorFieldApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        for character in "abc" { host.handle(.key(.character(character))) }
        host.handle(.key(.left))
        host.handle(.key(.backspace))
        #expect(app.text.get() == "ac")
    }

    @Test("Delete now removes the character at the cursor, not the whole field")
    func deleteIsForwardDeleteNotClearField() throws {
        let app = CursorFieldApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        for character in "abc" { host.handle(.key(.character(character))) }
        host.handle(.key(.home))
        host.handle(.key(.delete))
        #expect(app.text.get() == "bc")
    }

    @Test("backspace declines at the start of the field without a spurious dirty frame")
    func backspaceDeclinesAtStart() throws {
        let app = CursorFieldApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        let cleanAfterPump = host.needsFrame
        #expect(!cleanAfterPump)
        host.handle(.key(.backspace))
        let dirtyAfterBackspace = host.needsFrame
        #expect(!dirtyAfterBackspace)
        #expect(app.text.get() == "")
    }

    @Test(".up/.down still move focus spatially while a TextField is focused")
    func verticalArrowsStillNavigateFromTextField() throws {
        let app = CursorNavApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.down))
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.enter))
        #expect(app.counter.get() == 1)
    }

    @Test(".left/.right still move focus spatially when a Button, not a TextField, is focused")
    func horizontalArrowsStillNavigateBetweenButtons() throws {
        let app = HorizontalNavApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.right))
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.key(.enter))
        #expect(app.right.get() == 1)
        #expect(app.left.get() == 0)
    }
}

import Testing
@testable import GamaCore

@Suite
struct EngineTests {
    @Test func tabMovesFocusAndEnterTaps() {
        let root = VStack {
            Button("A", id: "a")
            Button("B", id: "b")
        }
        var engine = Engine(root: root, size: Size(width: 20, height: 5))
        #expect(engine.focus == NodeID("a"))
        #expect(engine.handle(.key(.tab)) == nil)
        #expect(engine.focus == NodeID("b"))
        #expect(engine.handle(.key(.enter)) == .tap("b"))
    }

    @Test func textFieldEditAndBackspace() {
        let root = TextField("hi", id: "n")
        var engine = Engine(root: root, size: Size(width: 20, height: 1))
        #expect(engine.handle(.key(.character("!"))) == .edit("n", "hi!"))
        engine.setRoot(TextField("hi!", id: "n"))
        #expect(engine.handle(.key(.backspace)) == .edit("n", "hi"))
    }

    @Test func listUpDownClamps() {
        let root = List(id: "l", selected: 0) {
            Text("0")
            Text("1")
        }
        var engine = Engine(root: root, size: Size(width: 10, height: 5))
        #expect(engine.handle(.key(.up)) == .select("l", 0))
        #expect(engine.handle(.key(.down)) == .select("l", 1))
    }

    @Test func hitTestButton() {
        let root = Button("OK", id: "ok")
        let box = Layout.layout(root, in: Size(width: 10, height: 1))
        #expect(HitTest.hit(box, at: Point(x: 1, y: 0)) == NodeID("ok"))
        #expect(HitTest.hit(box, at: Point(x: 0, y: 5)) == nil)
    }

    @Test func mousePressActivatesButton() {
        let root = Button("OK", id: "ok")
        var engine = Engine(root: root, size: Size(width: 10, height: 1))
        let ev = Event.mouse(Mouse(kind: .press, button: 0, x: 1, y: 0))
        #expect(engine.handle(ev) == .tap("ok"))
    }
}

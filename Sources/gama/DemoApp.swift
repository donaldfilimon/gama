import Darwin
import GamaCore
import GamaTUI

struct DemoState {
    var name: String = ""
    var ready: Bool = false
    var selected: Int = 0
    var quit: Bool = false
}

struct DemoApp {
    var state = DemoState()

    func body() -> ViewNode {
        let rows = ["alpha", "beta", "gamma"]
        return VStack(spacing: 1) {
            Text("gama demo")
            TextField(state.name, placeholder: "name", id: "name")
            Checkbox("ready", checked: state.ready, id: "ready")
            Progress(Double(state.name.count) / 16.0)
            List(id: "rows", selected: state.selected) {
                Text(state.selected == 0 ? "> \(rows[0])" : "  \(rows[0])")
                Text(state.selected == 1 ? "> \(rows[1])" : "  \(rows[1])")
                Text(state.selected == 2 ? "> \(rows[2])" : "  \(rows[2])")
            }
            HStack(spacing: 2) {
                Button("OK", id: "ok")
                Button("Quit", id: "quit")
            }
        }
    }

    mutating func reduce(_ action: Action) {
        switch action {
        case .edit("name", let text):
            state.name = text
        case .toggle("ready"):
            state.ready.toggle()
        case .select("rows", let index):
            state.selected = index
        case .tap("quit"):
            state.quit = true
        default:
            break
        }
    }

    func collectIDs(_ node: ViewNode) -> [NodeID] {
        FocusOrder.focusableIDs(node)
    }

    mutating func run() throws {
        let term = Terminal()
        try term.enterRawMode()
        defer { term.restore() }
        let size = (try? term.size()) ?? Size(width: 80, height: 24)
        var engine = Engine(root: body(), size: size)
        var previous = CellGrid(width: size.width, height: size.height)
        while !state.quit {
            engine.setRoot(body())
            let box = Layout.layout(engine.root, in: engine.size)
            var grid = CellGrid(width: engine.size.width, height: engine.size.height)
            Paint.paint(box, into: &grid, focus: engine.focus)
            let diff = ANSIDiff.encode(old: previous, new: grid)
            if !diff.isEmpty {
                try term.write(diff)
            }
            previous = grid
            if let event = try term.pollEvent() {
                if shouldQuit(event, focus: engine.focus) {
                    state.quit = true
                    continue
                }
                if let action = engine.handle(event) {
                    reduce(action)
                }
            } else {
                timespecSleep()
            }
        }
    }

    func shouldQuit(_ event: Event, focus: NodeID?) -> Bool {
        switch event {
        case .key(.ctrlC):
            return true
        case .key(.character("q")), .key(.character("Q")):
            return focus != NodeID("name")
        default:
            return false
        }
    }

    func timespecSleep() {
        var req = timespec(tv_sec: 0, tv_nsec: 16_000_000)
        nanosleep(&req, nil)
    }
}

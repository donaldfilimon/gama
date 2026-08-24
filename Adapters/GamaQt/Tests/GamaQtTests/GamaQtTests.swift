import CGamaQtAdapter
import GamaCore
import GamaDraw
import GamaQt
import Testing

@Test("Qt surface receives a Gama draw list")
func rendersFrame() {
    var surface = gama.QtSurface(10, 3)
    let list = DrawList(
        size: Size(width: 10, height: 3),
        commands: [
            .fillRect(Rect(x: 0, y: 0, width: 2, height: 1), Color(r: 20, g: 40, b: 60))
        ]
    )
    GamaQtRenderer.render(list, into: &surface)
    #expect(surface.pixelWidth() == 90)
    #expect(surface.pixelHeight() == 51)
}

@Test("Qt host translates input into a changed retained frame and shuts down")
func hostLifecycle() {
    struct Counter: App {
        let count = Signal(0)
        init() {}
        var content: some View {
            VStack {
                Text("Count \(count.get())")
                Button("Increment") { count.update { $0 += 1 } }
            }
        }
    }

    let host = GamaQtHost(app: Counter(), size: Size(width: 20, height: 4))
    let before = host.frame()
    host.handle(.pointer(Point(x: 1, y: 1), pressed: true))
    let after = host.frame()
    #expect(before != after)
    #expect(after.commands.contains { command in
        if case .text("Count 1", _, _) = command { return true }
        return false
    })
    host.shutdown()
}

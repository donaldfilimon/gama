import CGamaQtAdapter
import GamaCore
import GamaQt

private struct ExampleApp: App {
    init() {}
    var content: some View {
        VStack {
            Text("Gama + Qt").bold()
            Button("Action") {}
        }
    }
}

private let host = GamaQtHost(app: ExampleApp(), size: Size(width: 24, height: 6))
var surface = gama.QtSurface(24, 6)
host.render(into: &surface)
print("GamaQt example rendered \(surface.pixelWidth())x\(surface.pixelHeight()) pixels")
host.shutdown()

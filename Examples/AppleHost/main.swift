#if canImport(AppKit)
import AppKit
import GamaAppleUI
import GamaCore

struct AppleExample: App {
    init() {}
    var content: some View {
        VStack {
            Text("Gama Apple").bold()
            Button("Action") {}
        }
    }
}

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentView = GamaHostView(app: AppleExample())
window.makeKeyAndOrderFront(nil)
#endif

import Foundation

/// Platform initialization helper
private func initializePlatform() throws {
    #if os(Windows)
    // Windows-specific initialization
    let windowClass = WindowsWindowClass(name: "GameWindow")
    try windowClass.register { hwnd, uMsg, wParam, lParam in
        WindowsWindow.windowProc(hwnd: hwnd, uMsg: uMsg, wParam: wParam, lParam: lParam)
    }
    #elseif os(macOS) || os(iOS) || os(tvOS)
    // Apple platforms initialization (stub)
    // TODO: Implement Apple platform initialization
    #elseif os(Linux)
    // Linux initialization (stub)
    // TODO: Implement Linux platform initialization
    #elseif os(Android)
    // Android initialization (stub)
    // TODO: Implement Android platform initialization
    #endif
}

/// GameApp: Cross-platform main entry point
/// Uses the platform abstraction layer for windowing
@main
struct GameApp {
    private static var mainWindow: Window?
    private static var appDelegate: AppDelegate?

    /// Main entry point
    /// - Initializes platform components using the wrapper
    /// - Creates and shows the main window
    /// - Runs the message loop
    static func main() {
        do {
            try ensurePlatformSupport(for: "windowing", supported: hasWindowingSupport)

            // Initialize platform-specific components
            try initializePlatform()

            // Create delegate
            let delegate = AppDelegate()
            appDelegate = delegate

            // Create window using the platform abstraction
            let window = try Window(
                title: "Game Window",
                size: Size(width: 800, height: 600)
            )

            // Set delegate
            window.setDelegate(delegate)

            // Store reference
            mainWindow = window

            // Show window
            window.show()
            window.update()

            // Run message loop using platform abstraction
            let messageLoop = MessageLoop()
            _ = messageLoop.run()

        } catch {
            print("Error: \(error)")
        }
    }
}

/// App delegate implementing WindowDelegate
private class AppDelegate: WindowDelegate {
    func windowWillClose(_ window: WindowProtocol) -> Bool {
        // Show confirmation dialog before closing
        #if canImport(WinSDK)
        if let windowsWindow = window as? WindowsWindow {
            return MessageBox.confirm(title: "Game", message: "Really quit?", owner: windowsWindow)
        }
        #endif
        // Cross-platform dialog (stub - always allow close on other platforms)
        return true
    }

    func windowDidClose(_ window: WindowProtocol) {
        // Window closed
    }

    func windowWillDestroy(_ window: WindowProtocol) {
        // Window will be destroyed
    }
}
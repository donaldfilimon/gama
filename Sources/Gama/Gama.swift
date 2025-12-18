import Foundation

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

            // Create delegate
            let delegate = AppDelegate()
            appDelegate = delegate

            #if os(Windows)
            // Windows-specific initialization
            let windowClass = WindowsWindowClass(name: "GameWindow")
            try windowClass.register { hwnd, uMsg, wParam, lParam in
                WindowsWindow.windowProc(hwnd: hwnd, uMsg: uMsg, wParam: wParam, lParam: lParam)
            }
            #elseif os(macOS) || os(iOS) || os(tvOS)
            // Apple platforms initialization (stub)
            #elseif os(Linux)
            // Linux initialization (stub)
            #elseif os(Android)
            // Android initialization (stub)
            #endif

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

            // Run message loop
            #if os(Windows)
            let messageLoop = WindowsMessageLoop()
            _ = messageLoop.run()
            #elseif os(macOS) || os(iOS) || os(tvOS)
            // Apple message loop (stub)
            #elseif os(Linux)
            // Linux message loop (stub)
            #elseif os(Android)
            // Android message loop (stub)
            #else
            print("Message loop not implemented for platform: \(currentPlatform)")
            #endif

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
        let result = MessageBox.confirm(title: "Game", message: "Really quit?", owner: window as? WindowsWindow)
        return result
        #else
        // Cross-platform dialog (stub)
        return true
        #endif
    }

    func windowDidClose(_ window: WindowProtocol) {
        // Window closed
    }

    func windowWillDestroy(_ window: WindowProtocol) {
        // Window will be destroyed
    }
}
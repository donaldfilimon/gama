import Foundation
import WinSDK

/// GameApp: Main entry point for the Windows-based game application
/// Now using the comprehensive WinSDK wrapper
@main
struct GameApp {
    private static var mainWindow: Window?
    private static var appDelegate: AppDelegate?
    
    /// Main entry point
    /// - Initializes Windows components using the wrapper
    /// - Creates and shows the main window
    /// - Runs the message loop
    static func main() {
        do {
            // Create delegate
            let delegate = AppDelegate()
            appDelegate = delegate
            
            // Create window class
            let windowClass = WindowClass(name: "GameWindow")
            
            // Register window class with default settings
            try windowClass.register { hwnd, uMsg, wParam, lParam in
                Window.windowProc(hwnd: hwnd, uMsg: uMsg, wParam: wParam, lParam: lParam)
            }
            
            // Create window using the wrapper
            let window = try Window(
                className: "GameWindow",
                title: "Game Window",
                style: .overlappedWindow,
                size: Size(width: 800, height: 600)
            )
            
            // Set delegate
            window.delegate = delegate
            
            // Store reference
            mainWindow = window
            
            // Show window
            window.show()
            window.update()
            
            // Run message loop
            let messageLoop = MessageLoop()
            _ = messageLoop.run()
            
        } catch {
            print("Error: \(error)")
        }
    }
}

/// App delegate implementing WindowDelegate
private class AppDelegate: WindowDelegate {
    func windowWillClose(_ window: Window) -> Bool {
        // Show confirmation dialog before closing
        let result = MessageBox.confirm(title: "Game", message: "Really quit?", owner: window)
        return result
    }
    
    func windowDidClose(_ window: Window) {
        // Window closed
    }
    
    func windowWillDestroy(_ window: Window) {
        // Window will be destroyed
    }
}

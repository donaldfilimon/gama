import Gama

/// Multi-platform demo application
/// Demonstrates basic window creation and management across platforms
@main
struct MultiPlatformDemo {
    static func main() async {
        print("🎯 Starting Multi-Platform Demo on \(currentPlatform)")
        print("Capabilities: Windowing=\(hasWindowingSupport), Graphics=\(hasGraphicsSupport), Controls=\(hasControlSupport), Input=\(hasInputSupport)")

        do {
            // Test basic platform support
            try ensurePlatformSupport(for: "windowing", supported: hasWindowingSupport)

            // Create a demo window
            print("📱 Creating demo window...")
            let window = try Window(
                title: "Multi-Platform Demo - \(currentPlatform)",
                size: Size(width: 600, height: 400)
            )

            // Set up window delegate
            window.setDelegate(DemoWindowDelegate())

            print("✅ Window created successfully")
            print("   Title: \(window.title)")
            print("   Size: \(window.size.width) x \(window.size.height)")
            print("   Position: (\(window.position.x), \(window.position.y))")
            print("   Valid: \(window.isValid)")

            // Show the window
            window.show()
            print("🖥️  Window shown")

            // Test some window operations
            await testWindowOperations(window)

            // Test platform-specific features
            await testPlatformFeatures()

            print("🎉 Demo completed successfully!")

        } catch {
            print("❌ Demo failed: \(error)")
            if let platformError = error as? PlatformError {
                print("   Platform error details: \(platformError.description)")
            }
        }
    }

    static func testWindowOperations(_ window: Window) async {
        print("🔧 Testing window operations...")

        // Test window property changes
        window.title = "Updated Title - \(currentPlatform)"
        print("   Title updated to: \(window.title)")

        // Test positioning (if supported)
        let newPosition = Point(x: 100, y: 100)
        window.position = newPosition
        print("   Position set to: (\(window.position.x), \(window.position.y))")

        // Test sizing
        let newSize = Size(width: 500, height: 300)
        window.size = newSize
        print("   Size set to: \(window.size.width) x \(window.size.height)")

        // Test frame operations
        let newFrame = Rectangle(left: 150, top: 150, right: 650, bottom: 450)
        window.frame = newFrame
        print("   Frame set to: \(window.frame.width)x\(window.frame.height) at (\(window.frame.left), \(window.frame.top))")

        // Test visibility
        window.hide()
        print("   Window hidden")
        await Task.sleep(500_000_000) // 0.5 seconds

        window.show()
        print("   Window shown again")

        // Test update
        window.update()
        print("   Window updated")

        print("✅ Window operations completed")
    }

    static func testPlatformFeatures() async {
        print("🔧 Testing platform-specific features...")

        #if os(Windows)
        print("   Windows-specific: WinSDK integration ready")
        #elseif os(macOS)
        print("   macOS-specific: AppKit integration ready")
        #elseif os(iOS)
        print("   iOS-specific: UIKit integration ready")
        #elseif os(Linux)
        print("   Linux-specific: GTK integration ready (stub)")
        #endif

        // Test system info
        let sysInfo = AppleSystem.systemInfo
        print("   System: \(sysInfo.platform) \(sysInfo.version)")
        print("   CPU cores: \(sysInfo.processorCount) active: \(sysInfo.activeProcessorCount)")
        print("   Memory: \(sysInfo.physicalMemory / 1024 / 1024) MB")

        print("✅ Platform features tested")
    }
}

/// Demo window delegate
class DemoWindowDelegate: WindowDelegate {
    func windowWillClose(_ window: WindowProtocol) -> Bool {
        print("🔔 Window will close - showing confirmation")
        #if os(macOS)
        Task {
            let confirmed = await AppleDialogs.showConfirm(title: "Quit Demo", message: "Really close the demo window?")
            if confirmed {
                print("✅ User confirmed close")
            } else {
                print("❌ User cancelled close")
            }
        }
        #endif
        return true
    }

    func windowDidClose(_ window: WindowProtocol) {
        print("🔔 Window did close")
    }

    func windowDidResize(_ window: WindowProtocol, size: Size) {
        print("📏 Window resized to: \(size.width) x \(size.height)")
    }

    func windowDidMove(_ window: WindowProtocol, position: Point) {
        print("📍 Window moved to: (\(position.x), \(position.y))")
    }

    func windowDidActivate(_ window: WindowProtocol) {
        print("🎯 Window activated")
    }

    func windowDidDeactivate(_ window: WindowProtocol) {
        print("💤 Window deactivated")
    }

    func windowWillPaint(_ window: WindowProtocol) {
        print("🎨 Window will paint")
    }
}
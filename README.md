# Gama

A comprehensive **multi-platform GUI framework** for Swift, supporting Windows, macOS, iOS, Linux, and Android.

## 🚀 Features

- **Cross-platform**: Unified API across Windows, macOS, iOS, Linux, and Android
- **Native performance**: Direct platform API integration (WinSDK, AppKit, UIKit, GTK, Android SDK)
- **Swift-friendly**: Modern Swift interfaces with type safety and memory management
- **RAII design**: Automatic resource cleanup using Swift's `defer` and ARC
- **Comprehensive**: Windows, graphics, controls, input, dialogs, and system utilities
- **Extensible**: Platform abstraction layer allows easy addition of new platforms

## 📋 Platform Support Matrix

| Feature | Windows | macOS | iOS/iPadOS | Linux | Android |
|---------|---------|-------|------------|-------|---------|
| **Windows** | ✅ Full | ✅ AppKit | ✅ UIKit | 🚧 GTK | 🚧 JNI |
| **Graphics** | ✅ GDI+ | ✅ Core Graphics | ✅ Core Graphics | 🚧 Cairo | 🚧 Canvas |
| **Controls** | ✅ Win32 | ✅ AppKit | ✅ UIKit | 🚧 GTK | 🚧 Views |
| **Input** | ✅ Win32 | ✅ NSEvent | ✅ UIEvent | 🚧 GDK | 🚧 MotionEvent |
| **Dialogs** | ✅ Win32 | ✅ NSAlert | ✅ UIAlert | 🚧 GTK | 🚧 AlertDialog |
| **System** | ✅ Win32 | ✅ NSProcessInfo | ✅ UIDevice | 🚧 POSIX | 🚧 System |
| **Timers** | ✅ Win32 | 🚧 Foundation | 🚧 Foundation | 🚧 GLib | 🚧 Handler |
| **Build** | ✅ MSVC | ✅ Xcode | ✅ Xcode | ✅ GCC/Clang | 🚧 NDK |

✅ = Fully implemented | 🚧 = Stub implementation ready for enhancement

## 🏗️ Architecture

Gama uses a **platform abstraction layer**:

```
┌─────────────────┐
│   Public API    │  ← Window, WindowProtocol, WindowFactory
│   (Unified)     │
├─────────────────┤
│ Platform Layer  │  ← WindowsWindow, AppleWindow, LinuxWindow, AndroidWindow
│ (Platform-specific)|
├─────────────────┤
│  Core Types     │  ← Point, Size, Rectangle, Color (cross-platform)
│  (Shared)       │
└─────────────────┘
```

## 📦 Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/gama", from: "1.0.0")
]
```

## 🚀 Quick Start

### Basic Window Creation

```swift
import Gama

// Works on all platforms!
let window = try Window(
    title: "My App",
    size: Size(width: 800, height: 600)
)

window.show()
```

### Platform-Specific Code

```swift
import Gama

// Platform detection
if isWindows {
    // Windows-specific code
} else if isApple {
    // macOS/iOS code
} else if isLinux {
    // Linux code
}

// Safe platform checks
try ensurePlatformSupport(for: "graphics", supported: hasGraphicsSupport)
```

### Event Handling

```swift
class MyDelegate: WindowDelegate {
    func windowWillClose(_ window: WindowProtocol) -> Bool {
        // Return false to prevent closing
        return false
    }

    func windowDidResize(_ window: WindowProtocol, size: Size) {
        print("Window resized to: \(size.width) x \(size.height)")
    }
}

let window = try Window(title: "Events Demo")
window.setDelegate(MyDelegate())
```

## 🎨 Graphics

```swift
// Cross-platform graphics (when implemented)
let graphics = try AppleGraphics(width: 800, height: 600)
graphics.setFillColor(.blue)
graphics.fillRectangle(Rectangle(left: 0, top: 0, right: 400, height: 300))
```

## 🎛️ Controls

```swift
// Platform-specific controls
#if os(macOS)
let button = AppleButton(title: "Click Me")
button.setAction(self, action: #selector(buttonClicked))
#endif
```

## 🔧 Development

### Building

```bash
# Windows
swift build

# macOS/iOS
swift build -Xswiftc "-target" -Xswiftc "x86_64-apple-macos12"

# Linux
swift build
```

### Testing

```bash
swift test
```

### Examples

See `Examples/` directory for platform-specific demos:

- `MultiPlatformDemo` - Basic window and event demonstration

## 📚 Documentation

- [Platform Support Guide](Sources/Gama/PLATFORM_SUPPORT.md)
- [API Reference](docs/api/)
- [Migration Guide](docs/migration.md)

## 🤝 Contributing

1. **Platform Implementation**: Add support for new platforms by implementing the platform protocols
2. **Feature Enhancement**: Extend existing platform implementations
3. **Testing**: Add cross-platform tests
4. **Documentation**: Update platform support matrix and guides

### Adding a New Platform

1. Create `Platform/NewPlatform/` directory
2. Implement `WindowProtocol` with `NewPlatformWindow`
3. Add platform detection in `Core/Platform.swift`
4. Update `WindowFactory` to instantiate your implementation
5. Add to build system and documentation

## 📄 License

See [LICENSE.md](LICENSE.md) for details.

## 🙏 Acknowledgments

- Windows implementation based on WinSDK
- Apple implementation uses AppKit/UIKit and Core Graphics
- Linux implementation designed for GTK4 and Cairo
- Android implementation designed for JNI bridge

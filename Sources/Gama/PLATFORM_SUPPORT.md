# Multi-Platform Support

This framework supports cross-platform development across Windows, macOS, iOS, iPadOS, Linux, and Android using a unified API with platform-specific implementations.

## Architecture

The framework uses a **platform abstraction layer**:

1. **Core API**: Unified public interface (`Window`, `WindowProtocol`, etc.)
2. **Platform Layer**: Platform-specific implementations in `Platform/` directory
3. **Factory Pattern**: `WindowFactory` creates platform-appropriate instances
4. **Conditional Compilation**: `#if os()` and `#if canImport()` for platform detection

## Directory Structure

```
Sources/Gama/
├── Core/                    # Cross-platform foundation types
├── Platform/               # Platform-specific implementations
│   ├── Windows/           # Windows (WinSDK) implementation
│   │   ├── WindowsWindow.swift
│   │   ├── WindowsMessageLoop.swift
│   │   └── ...
│   ├── Apple/             # macOS/iOS/iPadOS (AppKit/UIKit)
│   │   └── AppleWindow.swift
│   ├── Linux/             # Linux (GTK4)
│   │   └── LinuxWindow.swift
│   └── Android/           # Android (JNI)
│       └── AndroidWindow.swift
├── Window/                 # Public Window API
│   ├── Window.swift       # Cross-platform Window class
│   ├── WindowProtocol.swift
│   └── WindowFactory.swift
└── ...                    # Other cross-platform modules
```

## Platform Support Matrix

| Feature | Windows | macOS | iOS/iPadOS | Linux | Android |
|---------|---------|-------|------------|-------|---------|
| Windows | ✅ | ✅ | ✅ | ✅ (GTK) | ✅ (JNI) |
| Graphics | ✅ (GDI) | 🚧 (Core Graphics) | 🚧 (Core Graphics) | 🚧 (Cairo) | 🚧 (Canvas) |
| Controls | ✅ | 🚧 (AppKit) | 🚧 (UIKit) | 🚧 (GTK) | 🚧 (Views) |
| Input | ✅ | 🚧 (NSEvent) | 🚧 (UIEvent) | 🚧 (GDK) | 🚧 (MotionEvent) |
| Dialogs | ✅ | 🚧 (NSAlert) | 🚧 (UIAlert) | 🚧 (GTK) | 🚧 (AlertDialog) |
| Timers | ✅ | 🚧 | 🚧 | 🚧 | 🚧 |
| System Info | ✅ | 🚧 | 🚧 | 🚧 | 🚧 |

✅ = Implemented
🚧 = Planned/Stub implementation

## Compilation

### Windows

```bash
swift build
# Full WinSDK functionality available
```

### macOS/iOS/iPadOS

```bash
swift build -Xswiftc "-target" -Xswiftc "x86_64-apple-macos12"
# Stub implementations with AppKit/UIKit placeholders
```

### Linux

```bash
swift build
# Requires GTK4 development libraries
# Stub implementations with GTK placeholders
```

### Android

```bash
# Requires Android NDK and custom build system
# Stub implementations with JNI placeholders
```

## Usage

### Cross-Platform Window Creation

```swift
import Gama

// Works on all platforms
let window = try Window(
    title: "My App",
    size: Size(width: 800, height: 600)
)

// Platform-specific behavior automatically selected
window.show()
```

### Platform Detection

```swift
import Gama

print("Running on: \(currentPlatform)")
print("Has windowing: \(hasWindowingSupport)")
print("Has graphics: \(hasGraphicsSupport)")
```

## Dependencies

### Linux

- GTK4 development libraries
- Cairo graphics library
- Swift GTK4 bindings package (when available)

### Apple Platforms

- Xcode (for iOS/macOS development)
- Core Graphics, AppKit, UIKit frameworks (system)

### Android

- Android NDK
- Android SDK
- Kotlin/Java helper library (to be created)
- Gradle build system integration

## Development Status

### Phase 1: Core Platform Abstraction ✅

- Platform detection utilities
- Unified protocols and interfaces
- Factory pattern for platform selection
- Windows implementation moved to Platform/Windows/

### Phase 2: Apple Platform Implementation 🚧

- Basic AppKit/UIKit window wrappers
- Core Graphics graphics integration
- Input event handling
- Native control bindings

### Phase 3: Linux Platform Implementation 🚧

- GTK4 Swift bindings integration
- Cairo graphics rendering
- GDK event handling
- Native widget support

### Phase 4: Android Platform Implementation 🚧

- JNI bridge infrastructure
- Android Activity integration
- Canvas graphics rendering
- Android View controls

### Phase 5: Feature Parity & Testing 🚧

- Cross-platform testing suite
- Documentation updates
- Example applications for each platform

## Testing

Run tests on each platform:

```bash
# Windows
swift test

# macOS
swift test -Xswiftc "-target" -Xswiftc "x86_64-apple-macos12"

# Linux (with GTK installed)
swift test
```

## Contributing

When implementing platform-specific features:

1. **Create platform-specific files** in `Platform/PlatformName/`
2. **Use platform guards** (`#if os(PlatformName)`)
3. **Implement protocols** from the Core API
4. **Update factory methods** to instantiate platform classes
5. **Add tests** for the new functionality
6. **Update documentation** with platform-specific notes

## Migration Guide

### From Windows-only to Multi-platform

**Before:**

```swift
// Windows-only code
let window = try Window(className: "MyWindow", title: "Title")
```

**After:**

```swift
// Cross-platform code
let window = try Window(title: "Title")
```

The platform-specific details are handled automatically by the factory pattern.

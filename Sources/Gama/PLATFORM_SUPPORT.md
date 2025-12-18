# Cross-Platform Support

This framework now supports cross-platform compilation using `#if canImport(WinSDK)` conditionals.

## Files with Platform Guards

All Windows-specific modules are wrapped with `#if canImport(WinSDK)` guards:
- Core module: Partially cross-platform (basic types work everywhere)
- Window module: Windows-only
- Graphics module: Windows-only  
- Controls module: Windows-only
- Input module: Windows-only
- System module: Windows-only
- COM module: Windows-only
- Timers module: Windows-only
- Dialogs module: Windows-only

## Compilation

- **Windows**: Full functionality when WinSDK is available
- **Other platforms**: Core types (Point, Size, Rectangle, Color) available, but Windows-specific APIs return stubs or throw PlatformError.notSupported

## Usage

On Windows:
```swift
import Gama
// Full functionality available
```

On other platforms:
```swift
import Gama
// Core types available, Windows APIs not available
```

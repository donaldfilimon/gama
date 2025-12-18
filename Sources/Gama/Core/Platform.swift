import Foundation

/// Platform detection utilities
#if os(Windows)
public let currentPlatform = "Windows"
public let isWindows = true
public let isApple = false
public let isLinux = false
public let isAndroid = false
#elseif os(macOS)
public let currentPlatform = "macOS"
public let isWindows = false
public let isApple = true
public let isLinux = false
public let isAndroid = false
#elseif os(iOS)
public let currentPlatform = "iOS"
public let isWindows = false
public let isApple = true
public let isLinux = false
public let isAndroid = false
#elseif os(tvOS)
public let currentPlatform = "tvOS"
public let isWindows = false
public let isApple = true
public let isLinux = false
public let isAndroid = false
#elseif os(watchOS)
public let currentPlatform = "watchOS"
public let isWindows = false
public let isApple = true
public let isLinux = false
public let isAndroid = false
#elseif os(Linux)
public let currentPlatform = "Linux"
public let isWindows = false
public let isApple = false
public let isLinux = true
public let isAndroid = false
#elseif os(Android)
public let currentPlatform = "Android"
public let isWindows = false
public let isApple = false
public let isLinux = false
public let isAndroid = true
#else
public let currentPlatform = "Unknown"
public let isWindows = false
public let isApple = false
public let isLinux = false
public let isAndroid = false
#endif

/// Check if the current platform supports windows
public let hasWindowingSupport: Bool = {
    #if os(Windows) || os(macOS) || os(iOS) || os(tvOS) || os(Linux) || os(Android)
    return true
    #else
    return false
    #endif
}()

/// Check if the current platform supports graphics
public let hasGraphicsSupport: Bool = {
    #if os(Windows) || os(macOS) || os(iOS) || os(tvOS) || os(Linux) || os(Android)
    return true
    #else
    return false
    #endif
}()

/// Check if the current platform supports controls/widgets
public let hasControlSupport: Bool = {
    #if os(Windows) || os(macOS) || os(iOS) || os(tvOS) || os(Linux) || os(Android)
    return true
    #else
    return false
    #endif
}()

/// Check if the current platform supports input handling
public let hasInputSupport: Bool = {
    #if os(Windows) || os(macOS) || os(iOS) || os(tvOS) || os(Linux) || os(Android)
    return true
    #else
    return false
    #endif
}()

/// Platform-specific capabilities
public struct PlatformCapabilities {
    public let windowing: Bool
    public let graphics: Bool
    public let controls: Bool
    public let input: Bool
    public let dialogs: Bool
    public let timers: Bool
    public let systemInfo: Bool

    public static let current = PlatformCapabilities(
        windowing: hasWindowingSupport,
        graphics: hasGraphicsSupport,
        controls: hasControlSupport,
        input: hasInputSupport,
        dialogs: hasWindowingSupport, // Dialogs typically require windowing
        timers: true, // All platforms support timers
        systemInfo: true // All platforms support basic system info
    )
}

/// Platform-specific error handling
public func ensurePlatformSupport(for feature: String, supported: Bool) throws {
    guard supported else {
        throw PlatformError.operationFailed(reason: "Feature '\(feature)' not supported on platform '\(currentPlatform)'")
    }
}

/// Assert that the current platform supports a feature
public func assertPlatformSupport(_ condition: Bool, _ message: String) {
    assert(condition, "Platform support assertion failed: \(message) (Platform: \(currentPlatform))")
}
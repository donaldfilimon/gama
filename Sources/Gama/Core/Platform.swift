import Foundation

/// Platform detection utilities
/// Centralized platform detection to reduce code duplication
private struct PlatformInfo {
    let name: String
    let isWindows: Bool
    let isApple: Bool
    let isLinux: Bool
    let isAndroid: Bool
}

#if os(Windows)
private let platformInfo = PlatformInfo(
    name: "Windows",
    isWindows: true,
    isApple: false,
    isLinux: false,
    isAndroid: false
)
#elseif os(macOS)
private let platformInfo = PlatformInfo(
    name: "macOS",
    isWindows: false,
    isApple: true,
    isLinux: false,
    isAndroid: false
)
#elseif os(iOS)
private let platformInfo = PlatformInfo(
    name: "iOS",
    isWindows: false,
    isApple: true,
    isLinux: false,
    isAndroid: false
)
#elseif os(tvOS)
private let platformInfo = PlatformInfo(
    name: "tvOS",
    isWindows: false,
    isApple: true,
    isLinux: false,
    isAndroid: false
)
#elseif os(watchOS)
private let platformInfo = PlatformInfo(
    name: "watchOS",
    isWindows: false,
    isApple: true,
    isLinux: false,
    isAndroid: false
)
#elseif os(Linux)
private let platformInfo = PlatformInfo(
    name: "Linux",
    isWindows: false,
    isApple: false,
    isLinux: true,
    isAndroid: false
)
#elseif os(Android)
private let platformInfo = PlatformInfo(
    name: "Android",
    isWindows: false,
    isApple: false,
    isLinux: false,
    isAndroid: true
)
#else
private let platformInfo = PlatformInfo(
    name: "Unknown",
    isWindows: false,
    isApple: false,
    isLinux: false,
    isAndroid: false
)
#endif

public let currentPlatform = platformInfo.name
public let isWindows = platformInfo.isWindows
public let isApple = platformInfo.isApple
public let isLinux = platformInfo.isLinux
public let isAndroid = platformInfo.isAndroid

/// Supported platforms for common features
private let supportedPlatforms: Bool = {
    #if os(Windows) || os(macOS) || os(iOS) || os(tvOS) || os(Linux) || os(Android)
    return true
    #else
    return false
    #endif
}()

/// Check if the current platform supports windows
public let hasWindowingSupport: Bool = supportedPlatforms

/// Check if the current platform supports graphics
public let hasGraphicsSupport: Bool = supportedPlatforms

/// Check if the current platform supports controls/widgets
public let hasControlSupport: Bool = supportedPlatforms

/// Check if the current platform supports input handling
public let hasInputSupport: Bool = supportedPlatforms

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
/// Swift 6.2: Enhanced with typed throws support
public func ensurePlatformSupport(for feature: String, supported: Bool) throws(PlatformError) {
    guard supported else {
        throw PlatformError.operationFailed(reason: "Feature '\(feature)' not supported on platform '\(currentPlatform)'")
    }
}

/// Assert that the current platform supports a feature
/// Swift 6.2: Enhanced with better error messages
public func assertPlatformSupport(_ condition: Bool, _ message: String) {
    assert(condition, "Platform support assertion failed: \(message) (Platform: \(currentPlatform))")
}

/// Swift 6.2: Type-safe platform feature checking
@inlinable
public func hasPlatformFeature(_ feature: PlatformCapabilities.Feature) -> Bool {
    switch feature {
    case .windowing:
        return PlatformCapabilities.current.windowing
    case .graphics:
        return PlatformCapabilities.current.graphics
    case .controls:
        return PlatformCapabilities.current.controls
    case .input:
        return PlatformCapabilities.current.input
    case .dialogs:
        return PlatformCapabilities.current.dialogs
    case .timers:
        return PlatformCapabilities.current.timers
    case .systemInfo:
        return PlatformCapabilities.current.systemInfo
    }
}

/// Swift 6.2: Platform feature enumeration
extension PlatformCapabilities {
    public enum Feature: Sendable {
        case windowing
        case graphics
        case controls
        case input
        case dialogs
        case timers
        case systemInfo
    }
}
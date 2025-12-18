import Foundation

/// Swift 6.2: Platform-specific code helpers using modern Swift features
/// These provide compile-time platform detection and code generation

/// Platform enumeration for type-safe platform detection
public enum Platform: String, Sendable {
    case windows
    case macOS
    case iOS
    case tvOS
    case watchOS
    case linux
    case android
    
    /// Get the current platform at runtime
    public static var current: Platform {
        #if os(Windows)
        return .windows
        #elseif os(macOS)
        return .macOS
        #elseif os(iOS)
        return .iOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(Linux)
        return .linux
        #elseif os(Android)
        return .android
        #else
        fatalError("Unknown platform")
        #endif
    }
}

/// Swift 6.2: Type-safe platform-specific value provider
/// Usage: let value = platformValue(windows: 1, apple: 2, linux: 3)
@inlinable
public func platformValue<T>(
    windows: @autoclosure () -> T,
    apple: @autoclosure () -> T,
    linux: @autoclosure () -> T,
    android: @autoclosure () -> T = linux()
) -> T {
    #if os(Windows)
    return windows()
    #elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    return apple()
    #elseif os(Linux)
    return linux()
    #elseif os(Android)
    return android()
    #else
    return linux()
    #endif
}

/// Swift 6.2: Platform-specific optional value provider
@inlinable
public func platformValue<T>(
    windows: (() -> T)? = nil,
    apple: (() -> T)? = nil,
    linux: (() -> T)? = nil,
    android: (() -> T)? = nil
) -> T? {
    #if os(Windows)
    return windows?()
    #elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    return apple?()
    #elseif os(Linux)
    return linux?()
    #elseif os(Android)
    return android?()
    #else
    return nil
    #endif
}

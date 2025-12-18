import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Platform-agnostic error type
/// Swift 6.2: Enhanced with typed throws support
public enum PlatformError: Error, CustomStringConvertible, @retroactive Sendable {
    #if canImport(WinSDK)
    case lastError(code: DWORD)
    #else
    case systemError(code: Int32)
    #endif
    case invalidParameter
    case invalidHandle
    case operationFailed(reason: String)
    #if !canImport(WinSDK)
    case notSupported
    #endif
    
    #if canImport(WinSDK)
    /// Create a PlatformError from GetLastError()
    public static func fromLastError() -> PlatformError {
        return .lastError(code: GetLastError())
    }
    
    /// Create a PlatformError with a custom message
    public static func fromErrorCode(_ code: DWORD) -> PlatformError {
        return .lastError(code: code)
    }
    #else
    /// Create a PlatformError from system error
    public static func fromSystemError() -> PlatformError {
        return .systemError(code: errno)
    }
    
    /// Create a PlatformError with a custom error code
    public static func fromErrorCode(_ code: Int32) -> PlatformError {
        return .systemError(code: code)
    }
    #endif
    
    public var description: String {
        switch self {
        #if canImport(WinSDK)
        case .lastError(let code):
            return "Windows error code: \(code) (0x\(String(code, radix: 16)))"
        #else
        case .systemError(let code):
            return "System error code: \(code)"
        case .notSupported:
            return "Operation not supported on this platform"
        #endif
        case .invalidParameter:
            return "Invalid parameter"
        case .invalidHandle:
            return "Invalid handle"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
    
    /// Get the error code if available
    #if canImport(WinSDK)
    public var errorCode: DWORD? {
        switch self {
        case .lastError(let code):
            return code
        default:
            return nil
        }
    }
    #else
    public var errorCode: Int32? {
        switch self {
        case .systemError(let code):
            return code
        default:
            return nil
        }
    }
    #endif
}

#if canImport(WinSDK)
/// Windows-specific error type alias
public typealias WindowsError = PlatformError
#else
/// Windows-specific error type (not available on non-Windows platforms)
public enum WindowsError: Error {
    case notAvailableOnThisPlatform
}
#endif

/// Helper to check platform API return values and throw on error
internal func checkPlatformError(_ success: Bool) throws {
    guard success else {
        #if canImport(WinSDK)
        throw PlatformError.fromLastError()
        #else
        throw PlatformError.fromSystemError()
        #endif
    }
}

/// Legacy name for compatibility
internal func checkWindowsError(_ success: Bool) throws {
    try checkPlatformError(success)
}

/// Helper to check if a handle is valid and throw on error
internal func checkHandle<T>(_ handle: T?) throws -> T {
    guard let handle = handle else {
        #if canImport(WinSDK)
        throw PlatformError.fromLastError()
        #else
        throw PlatformError.invalidHandle
        #endif
    }
    return handle
}
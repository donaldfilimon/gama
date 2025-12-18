import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Platform-agnostic error type (Windows-specific implementation)
#if canImport(WinSDK)
public enum PlatformError: Error, CustomStringConvertible {
    case lastError(code: DWORD)
    case invalidParameter
    case invalidHandle
    case operationFailed(reason: String)
    
    /// Create a PlatformError from GetLastError()
    public static func fromLastError() -> PlatformError {
        return .lastError(code: GetLastError())
    }
    
    /// Create a PlatformError with a custom message
    public static func fromErrorCode(_ code: DWORD) -> PlatformError {
        return .lastError(code: code)
    }
    
    public var description: String {
        switch self {
        case .lastError(let code):
            return "Windows error code: \(code) (0x\(String(code, radix: 16)))"
        case .invalidParameter:
            return "Invalid parameter"
        case .invalidHandle:
            return "Invalid handle"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
    
    /// Get the error code if available
    public var errorCode: DWORD? {
        switch self {
        case .lastError(let code):
            return code
        default:
            return nil
        }
    }
}

/// Windows-specific error type alias
public typealias WindowsError = PlatformError
#else
/// Platform-agnostic error type (non-Windows implementation)
public enum PlatformError: Error, CustomStringConvertible {
    case systemError(code: Int32)
    case invalidParameter
    case invalidHandle
    case operationFailed(reason: String)
    case notSupported
    
    public var description: String {
        switch self {
        case .systemError(let code):
            return "System error code: \(code)"
        case .invalidParameter:
            return "Invalid parameter"
        case .invalidHandle:
            return "Invalid handle"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        case .notSupported:
            return "Operation not supported on this platform"
        }
    }
    
    /// Get the error code if available
    public var errorCode: Int32? {
        switch self {
        case .systemError(let code):
            return code
        default:
            return nil
        }
    }
}

/// Windows-specific error type (not available on non-Windows platforms)
public enum WindowsError: Error {
    case notAvailableOnThisPlatform
}
#endif

/// Helper to check platform API return values and throw on error
internal func checkWindowsError(_ success: Bool) throws {
    guard success else {
        #if canImport(WinSDK)
        throw PlatformError.fromLastError()
        #else
        throw PlatformError.systemError(code: errno)
        #endif
    }
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
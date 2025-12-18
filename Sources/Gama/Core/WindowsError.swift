import Foundation
import WinSDK

/// Windows API error type
public enum WindowsError: Error, CustomStringConvertible {
    case lastError(code: DWORD)
    case invalidParameter
    case invalidHandle
    case operationFailed(reason: String)
    
    /// Create a WindowsError from GetLastError()
    public static func fromLastError() -> WindowsError {
        return .lastError(code: GetLastError())
    }
    
    /// Create a WindowsError with a custom message
    public static func fromErrorCode(_ code: DWORD) -> WindowsError {
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

/// Helper to check Windows API return values and throw on error
internal func checkWindowsError(_ success: Bool) throws {
    guard success else {
        throw WindowsError.fromLastError()
    }
}

/// Helper to check if a handle is valid and throw on error
internal func checkHandle<T>(_ handle: T?) throws -> T {
    guard let handle = handle else {
        throw WindowsError.fromLastError()
    }
    return handle
}
import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Enhanced string conversion utilities for Windows API
extension String {
    #if canImport(WinSDK)
    /// Convert String to LPCWSTR (Windows UTF-16 string pointer)
    /// Note: The pointer is only valid during the closure execution
    /// For longer-lived strings, use withWindowsUTF16Buffer
    public func withWindowsUTF16<T>(_ body: (LPCWSTR) throws -> T) rethrows -> T {
        let utf16 = Array(self.utf16)
        return try utf16.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                // Return a null pointer
                let nullPtr = UnsafePointer<WCHAR>(bitPattern: 0)!
                return try body(nullPtr)
            }
            return try body(baseAddress)
        }
    }
    
    /// Convert String to Windows UTF-16 buffer array
    public func toWindowsUTF16() -> [WCHAR] {
        return Array(self.utf16)
    }
    
    /// Convert String to null-terminated Windows UTF-16 buffer
    public func toWindowsUTF16NullTerminated() -> [WCHAR] {
        var utf16 = Array(self.utf16)
        utf16.append(0) // Add null terminator
        return utf16
    }
    
    /// Create String from Windows UTF-16 buffer
    public static func fromWindowsUTF16(_ ptr: LPCWSTR, length: Int? = nil) -> String? {
        guard let ptr = ptr else { return nil }
        
        if let length = length {
            let buffer = UnsafeBufferPointer(start: ptr, count: length)
            return String(decoding: buffer, as: UTF16.self)
        }
        
        // Find null terminator
        var len = 0
        while ptr[len] != 0 {
            len += 1
        }
        
        let buffer = UnsafeBufferPointer(start: ptr, count: len)
        return String(decoding: buffer, as: UTF16.self)
    }
    
    /// Create String from Windows UTF-16 buffer (assumes null-terminated)
    public init?(windowsUTF16: LPCWSTR) {
        guard let windowsUTF16 = windowsUTF16 else { return nil }
        var len = 0
        while windowsUTF16[len] != 0 {
            len += 1
        }
        let buffer = UnsafeBufferPointer(start: windowsUTF16, count: len)
        self.init(decoding: buffer, as: UTF16.self)
    }
    
    /// Legacy property for backwards compatibility
    /// Note: This is unsafe for long-lived use - prefer withWindowsUTF16
    public var windowsUTF16: LPCWSTR {
        let utf16 = Array(self.utf16)
        return utf16.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else {
                return UnsafePointer<WCHAR>(bitPattern: 0)!
            }
            return baseAddress
        }
    }
    #else
    /// Cross-platform UTF-16 conversion (stub for non-Windows platforms)
    public func toWindowsUTF16() -> [UInt16] {
        return Array(self.utf16)
    }
    
    /// Cross-platform UTF-16 conversion with null terminator (stub for non-Windows platforms)
    public func toWindowsUTF16NullTerminated() -> [UInt16] {
        var utf16 = Array(self.utf16)
        utf16.append(0)
        return utf16
    }
    #endif
}
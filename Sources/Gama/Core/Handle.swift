import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Generic handle wrapper with automatic cleanup (RAII pattern)
public class Handle<T> {
    private var _handle: T?
    private let cleanup: (T) -> Void
    private let isValid: (T?) -> Bool
    
    /// Initialize with a handle and cleanup function
    public init(_ handle: T?, isValid: @escaping (T?) -> Bool = { $0 != nil }, cleanup: @escaping (T) -> Void) {
        self._handle = handle
        self.isValid = isValid
        self.cleanup = cleanup
    }
    
    /// Get the underlying handle
    public var handle: T? {
        return _handle
    }
    
    /// Check if the handle is valid
    public var isValidHandle: Bool {
        return isValid(_handle)
    }
    
    /// Release the handle (call cleanup and set to nil)
    public func release() {
        if let handle = _handle, isValid(handle) {
            cleanup(handle)
        }
        _handle = nil
    }
    
    deinit {
        release()
    }
}

#if canImport(WinSDK)
/// Specialized handle wrapper for HWND
public class WindowHandle: Handle<HWND> {
    public init(_ hwnd: HWND?) {
        super.init(hwnd, isValid: { $0 != nil && IsWindow($0) != 0 }) { hwnd in
            if IsWindow(hwnd) != 0 {
                DestroyWindow(hwnd)
            }
        }
    }
}

/// Specialized handle wrapper for HDC
public class DeviceContextHandle: Handle<HDC> {
    public init(_ hdc: HDC?, autoRelease: Bool = false) {
        super.init(hdc, isValid: { $0 != nil }) { hdc in
            if autoRelease {
                ReleaseDC(nil, hdc)
            } else {
                DeleteDC(hdc)
            }
        }
    }
}

/// Specialized handle wrapper for HMODULE
public class ModuleHandle: Handle<HMODULE> {
    public init(_ hModule: HMODULE?, freeLibrary: Bool = false) {
        super.init(hModule, isValid: { $0 != nil }) { hModule in
            if freeLibrary {
                FreeLibrary(hModule)
            }
        }
    }
}
#else
/// Cross-platform handle wrappers (stubs for non-Windows platforms)
public class WindowHandle: Handle<UnsafeMutableRawPointer?> {
    public init(_ hwnd: UnsafeMutableRawPointer?) {
        super.init(hwnd) { _ in }
    }
}

public class DeviceContextHandle: Handle<UnsafeMutableRawPointer?> {
    public init(_ hdc: UnsafeMutableRawPointer?, autoRelease: Bool = false) {
        super.init(hdc) { _ in }
    }
}

public class ModuleHandle: Handle<UnsafeMutableRawPointer?> {
    public init(_ hModule: UnsafeMutableRawPointer?, freeLibrary: Bool = false) {
        super.init(hModule) { _ in }
    }
}
#endif
import Foundation
import WinSDK

/// IUnknown wrapper for COM interop
public class IUnknownWrapper {
    private var ptr: UnsafeMutableRawPointer?
    
    public init(_ ptr: UnsafeMutableRawPointer?) {
        self.ptr = ptr
    }
    
    /// Add reference
    public func addRef() -> ULONG {
        guard let ptr = ptr else { return 0 }
        let vtable = ptr.assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutableRawPointer?>.self).pointee
        let addRefFunc = unsafeBitCast(vtable?[1], to: (@convention(c) (UnsafeMutableRawPointer?) -> ULONG).self)
        return addRefFunc(ptr)
    }
    
    /// Release reference
    public func release() -> ULONG {
        guard let ptr = ptr else { return 0 }
        let vtable = ptr.assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutableRawPointer?>.self).pointee
        let releaseFunc = unsafeBitCast(vtable?[2], to: (@convention(c) (UnsafeMutableRawPointer?) -> ULONG).self)
        let result = releaseFunc(ptr)
        if result == 0 {
            self.ptr = nil
        }
        return result
    }
    
    /// Query interface
    public func queryInterface(_ iid: inout GUID) -> UnsafeMutableRawPointer? {
        guard let ptr = ptr else { return nil }
        var result: UnsafeMutableRawPointer? = nil
        let vtable = ptr.assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutableRawPointer?>.self).pointee
        let queryInterfaceFunc = unsafeBitCast(vtable?[0], to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<GUID>, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT).self)
        _ = queryInterfaceFunc(ptr, &iid, &result)
        return result
    }
    
    deinit {
        if ptr != nil {
            _ = release()
        }
    }
}
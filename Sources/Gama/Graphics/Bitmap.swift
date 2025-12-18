import Foundation
import WinSDK

/// Bitmap wrapper for GDI bitmap objects
public class Bitmap {
    private let handle: BitmapHandleWrapper
    private let width: Int32
    private let height: Int32
    
    public var hBitmap: HBITMAP? {
        return handle.handle
    }
    
    public var size: Size {
        return Size(width: width, height: height)
    }
    
    /// Create a bitmap from an existing HBITMAP
    public init(hBitmap: HBITMAP) throws {
        self.handle = BitmapHandle(hBitmap) { bitmap in
            DeleteObject(HGDIOBJ(bitmap))
        }
        
        // Get bitmap dimensions
        var bm = BITMAP()
        guard GetObjectW(HGDIOBJ(hBitmap), Int32(MemoryLayout<BITMAP>.size), &bm) != 0 else {
            throw WindowsError.fromLastError()
        }
        
        self.width = bm.bmWidth
        self.height = bm.bmHeight
    }
    
    /// Create a compatible bitmap
    public init(deviceContext: DeviceContext, width: Int32, height: Int32) throws {
        guard let hDC = deviceContext.hDC else {
            throw WindowsError.invalidHandle
        }
        
        let hBitmap = CreateCompatibleBitmap(hDC, width, height)
        guard let hBitmap = hBitmap else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = BitmapHandle(hBitmap) { bitmap in
            DeleteObject(HGDIOBJ(bitmap))
        }
        self.width = width
        self.height = height
    }
    
    /// Create a DIB (Device Independent Bitmap)
    public init(
        width: Int32,
        height: Int32,
        planes: UInt16 = 1,
        bitsPerPixel: UInt16 = 32,
        bits: UnsafeMutableRawPointer? = nil
    ) throws {
        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = UINT(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = width
        bmi.bmiHeader.biHeight = height
        bmi.bmiHeader.biPlanes = planes
        bmi.bmiHeader.biBitCount = bitsPerPixel
        bmi.bmiHeader.biCompression = BI_RGB
        
        var bitsPtr: UnsafeMutableRawPointer? = nil
        let hBitmap = CreateDIBSection(
            nil,
            &bmi,
            DIB_RGB_COLORS,
            &bitsPtr,
            nil,
            0
        )
        
        guard let hBitmap = hBitmap else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = BitmapHandle(hBitmap) { bitmap in
            DeleteObject(HGDIOBJ(bitmap))
        }
        self.width = width
        self.height = height
    }
}

/// Specialized handle wrapper for HBITMAP
public class BitmapHandleWrapper: Handle<HBITMAP> {
    public init(_ hBitmap: HBITMAP?, cleanup: @escaping (HBITMAP) -> Void) {
        super.init(hBitmap, cleanup: cleanup)
    }
}
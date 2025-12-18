import Foundation
import WinSDK

/// Device context wrapper for GDI device contexts
public class DeviceContext {
    private let handle: DeviceContextHandle
    private let isWindowDC: Bool
    
    public var hDC: HDC? {
        return handle.handle
    }
    
    /// Create a device context for a window
    public init(window: Window) throws {
        guard let hwnd = window.hwnd else {
            throw WindowsError.invalidHandle
        }
        
        let hDC = GetDC(hwnd)
        guard let hDC = hDC else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = DeviceContextHandle(hDC, autoRelease: true)
        self.isWindowDC = true
    }
    
    /// Create a device context from an existing HDC
    public init(hDC: HDC, autoRelease: Bool = false) {
        self.handle = DeviceContextHandle(hDC, autoRelease: autoRelease)
        self.isWindowDC = false
    }
    
    /// Create a memory device context compatible with another DC
    public init(compatibleWith dc: DeviceContext) throws {
        guard let hDC = dc.hDC else {
            throw WindowsError.invalidHandle
        }
        
        let hMemDC = CreateCompatibleDC(hDC)
        guard let hMemDC = hMemDC else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = DeviceContextHandle(hMemDC, autoRelease: false)
        self.isWindowDC = false
    }
    
    /// Select an object into the device context
    @discardableResult
    public func selectObject<T>(_ object: T) -> HGDIOBJ? {
        guard let hDC = handle.handle else { return nil }
        
        let hObj: HGDIOBJ
        if let pen = object as? Pen, let hPen = pen.hPen {
            hObj = HGDIOBJ(hPen)
        } else if let brush = object as? Brush, let hBrush = brush.hBrush {
            hObj = HGDIOBJ(hBrush)
        } else if let font = object as? Font, let hFont = font.hFont {
            hObj = HGDIOBJ(hFont)
        } else if let bitmap = object as? Bitmap, let hBitmap = bitmap.hBitmap {
            hObj = HGDIOBJ(hBitmap)
        } else {
            return nil
        }
        
        return SelectObject(hDC, hObj)
    }
    
    /// Set text color
    public func setTextColor(_ color: Color) -> Color {
        guard let hDC = handle.handle else { return Color.black }
        let oldColor = SetTextColor(hDC, color.colorRef)
        return Color(DWORD(oldColor))
    }
    
    /// Set background color
    public func setBackgroundColor(_ color: Color) -> Color {
        guard let hDC = handle.handle else { return Color.white }
        let oldColor = SetBkColor(hDC, color.colorRef)
        return Color(DWORD(oldColor))
    }
    
    /// Set background mode
    public func setBackgroundMode(_ opaque: Bool) -> Int32 {
        guard let hDC = handle.handle else { return 0 }
        return SetBkMode(hDC, opaque ? OPAQUE : TRANSPARENT)
    }
    
    /// Draw a line
    public func drawLine(from start: Point, to end: Point) -> Bool {
        guard let hDC = handle.handle else { return false }
        return MoveToEx(hDC, start.x, start.y, nil) != 0 && 
               LineTo(hDC, end.x, end.y) != 0
    }
    
    /// Draw a rectangle
    public func drawRectangle(_ rect: Rectangle) -> Bool {
        guard let hDC = handle.handle else { return false }
        var winRect = rect.win32Rect
        return Rectangle(hDC, winRect.left, winRect.top, winRect.right, winRect.bottom) != 0
    }
    
    /// Fill a rectangle
    public func fillRectangle(_ rect: Rectangle, brush: Brush) -> Bool {
        guard let hDC = handle.handle, let hBrush = brush.hBrush else { return false }
        var winRect = rect.win32Rect
        return FillRect(hDC, &winRect, hBrush) != 0
    }
    
    /// Draw an ellipse
    public func drawEllipse(_ rect: Rectangle) -> Bool {
        guard let hDC = handle.handle else { return false }
        var winRect = rect.win32Rect
        return Ellipse(hDC, winRect.left, winRect.top, winRect.right, winRect.bottom) != 0
    }
    
    /// Draw text
    public func drawText(_ text: String, in rect: Rectangle, format: UINT = 0) -> Int32 {
        guard let hDC = handle.handle else { return 0 }
        var winRect = rect.win32Rect
        return text.withWindowsUTF16 { textPtr in
            DrawTextW(hDC, textPtr, Int32(text.utf16.count), &winRect, format)
        }
    }
    
    /// Get text metrics
    public func getTextMetrics() throws -> TEXTMETRICW {
        guard let hDC = handle.handle else {
            throw WindowsError.invalidHandle
        }
        var tm = TEXTMETRICW()
        guard GetTextMetricsW(hDC, &tm) != 0 else {
            throw WindowsError.fromLastError()
        }
        return tm
    }
    
    /// Bit blit (copy pixels from source DC)
    public func bitBlt(
        from source: DeviceContext,
        sourceRect: Rectangle,
        destPoint: Point,
        rasterOp: DWORD = SRCCOPY
    ) -> Bool {
        guard let hDestDC = handle.handle, let hSrcDC = source.hDC else {
            return false
        }
        return BitBlt(
            hDestDC,
            destPoint.x, destPoint.y,
            sourceRect.width, sourceRect.height,
            hSrcDC,
            sourceRect.left, sourceRect.top,
            rasterOp
        ) != 0
    }
    
    /// Stretch blit (copy and stretch pixels from source DC)
    public func stretchBlt(
        from source: DeviceContext,
        sourceRect: Rectangle,
        destRect: Rectangle,
        rasterOp: DWORD = SRCCOPY
    ) -> Bool {
        guard let hDestDC = handle.handle, let hSrcDC = source.hDC else {
            return false
        }
        var srcRect = sourceRect.win32Rect
        var dstRect = destRect.win32Rect
        return StretchBlt(
            hDestDC,
            dstRect.left, dstRect.top, dstRect.right - dstRect.left, dstRect.bottom - dstRect.top,
            hSrcDC,
            srcRect.left, srcRect.top, srcRect.right - srcRect.left, srcRect.bottom - srcRect.top,
            rasterOp
        ) != 0
    }
}
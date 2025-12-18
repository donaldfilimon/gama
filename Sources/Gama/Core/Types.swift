import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

#if canImport(WinSDK)
/// Swift-friendly type aliases for Windows types
public typealias WindowsHandle = HANDLE
public typealias WindowHandle = HWND
public typealias DeviceContext = HDC
public typealias ModuleHandle = HMODULE
public typealias IconHandle = HICON
public typealias CursorHandle = HCURSOR
public typealias BrushHandle = HBRUSH
public typealias PenHandle = HPEN
public typealias FontHandle = HFONT
public typealias BitmapHandle = HBITMAP
#else
/// Cross-platform handle types (opaque on non-Windows platforms)
public typealias WindowsHandle = UnsafeMutableRawPointer?
public typealias WindowHandle = UnsafeMutableRawPointer?
public typealias DeviceContext = UnsafeMutableRawPointer?
public typealias ModuleHandle = UnsafeMutableRawPointer?
public typealias IconHandle = UnsafeMutableRawPointer?
public typealias CursorHandle = UnsafeMutableRawPointer?
public typealias BrushHandle = UnsafeMutableRawPointer?
public typealias PenHandle = UnsafeMutableRawPointer?
public typealias FontHandle = UnsafeMutableRawPointer?
public typealias BitmapHandle = UnsafeMutableRawPointer?
#endif

/// Point structure
public struct Point {
    public var x: Int32
    public var y: Int32
    
    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
    
    #if canImport(WinSDK)
    public init(_ point: POINT) {
        self.x = point.x
        self.y = point.y
    }
    
    public var win32Point: POINT {
        return POINT(x: x, y: y)
    }
    #endif
}

/// Size structure
public struct Size {
    public var width: Int32
    public var height: Int32
    
    public init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }
    
    #if canImport(WinSDK)
    public init(_ size: SIZE) {
        self.width = size.cx
        self.height = size.cy
    }
    
    public var win32Size: SIZE {
        return SIZE(cx: width, cy: height)
    }
    #endif
}

/// Rectangle structure
public struct Rectangle {
    public var left: Int32
    public var top: Int32
    public var right: Int32
    public var bottom: Int32
    
    public init(left: Int32, top: Int32, right: Int32, bottom: Int32) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
    
    public init(x: Int32, y: Int32, width: Int32, height: Int32) {
        self.left = x
        self.top = y
        self.right = x + width
        self.bottom = y + height
    }
    
    #if canImport(WinSDK)
    public init(_ rect: RECT) {
        self.left = rect.left
        self.top = rect.top
        self.right = rect.right
        self.bottom = rect.bottom
    }
    
    public var win32Rect: RECT {
        var rect = RECT()
        rect.left = left
        rect.top = top
        rect.right = right
        rect.bottom = bottom
        return rect
    }
    #endif
    
    public var width: Int32 {
        return right - left
    }
    
    public var height: Int32 {
        return bottom - top
    }
    
    public var origin: Point {
        return Point(x: left, y: top)
    }
    
    public var size: Size {
        return Size(width: width, height: height)
    }
}

/// Color structure (RGB)
public struct Color {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    
    #if canImport(WinSDK)
    public init(_ rgb: DWORD) {
        self.red = UInt8(rgb & 0x000000FF)
        self.green = UInt8((rgb & 0x0000FF00) >> 8)
        self.blue = UInt8((rgb & 0x00FF0000) >> 16)
    }
    
    public var rgb: DWORD {
        return DWORD(red) | (DWORD(green) << 8) | (DWORD(blue) << 16)
    }
    
    /// Create COLORREF (Windows color reference)
    public var colorRef: COLORREF {
        return COLORREF(rgb)
    }
    #else
    /// Get RGB value as UInt32
    public var rgbValue: UInt32 {
        return UInt32(red) | (UInt32(green) << 8) | (UInt32(blue) << 16)
    }
    #endif
    
    // Common colors
    public static let black = Color(red: 0, green: 0, blue: 0)
    public static let white = Color(red: 255, green: 255, blue: 255)
    public static let red = Color(red: 255, green: 0, blue: 0)
    public static let green = Color(red: 0, green: 255, blue: 0)
    public static let blue = Color(red: 0, green: 0, blue: 255)
}

/// Extended Point with floating point
public struct PointF {
    public var x: Double
    public var y: Double
    
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    
    public func toPoint() -> Point {
        return Point(x: Int32(x), y: Int32(y))
    }
}

/// Extended Size with floating point
public struct SizeF {
    public var width: Double
    public var height: Double
    
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
    
    public func toSize() -> Size {
        return Size(width: Int32(width), height: Int32(height))
    }
}
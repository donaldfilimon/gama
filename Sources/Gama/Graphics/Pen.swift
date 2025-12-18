import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Pen styles
#if canImport(WinSDK)
public enum PenStyle: Int32 {
    case solid = 0
    case dash = 1
    case dot = 2
    case dashDot = 3
    case dashDotDot = 4
    case null = 5
    case insideFrame = 6
    
    public var win32Style: Int32 {
        switch self {
        case .solid: return PS_SOLID
        case .dash: return PS_DASH
        case .dot: return PS_DOT
        case .dashDot: return PS_DASHDOT
        case .dashDotDot: return PS_DASHDOTDOT
        case .null: return PS_NULL
        case .insideFrame: return PS_INSIDEFRAME
        }
    }
}

/// Pen wrapper for GDI pen objects
public class Pen {
    private let handle: PenHandleWrapper
    private let color: Color
    private let style: PenStyle
    private let width: Int32
    
    public var hPen: HPEN? {
        return handle.handle
    }
    
    /// Create a pen
    public init(color: Color, width: Int32 = 1, style: PenStyle = .solid) throws {
        self.color = color
        self.width = width
        self.style = style
        
        let hPen = CreatePen(style.win32Style, width, color.colorRef)
        guard let hPen = hPen else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = PenHandleWrapper(hPen) { pen in
            DeleteObject(HGDIOBJ(pen))
        }
    }
    
    /// Create a pen with extended style
    public init(extendedStyle: DWORD, width: Int32, brush: HBRUSH, styleArray: [DWORD]? = nil) throws {
        self.color = Color.black
        self.width = width
        self.style = .solid
        
        let hPen = styleArray?.withUnsafeBufferPointer { arrayPtr in
            CreatePenEx(extendedStyle, width, brush, arrayPtr.baseAddress.map { DWORD($0.count) } ?? 0, arrayPtr.baseAddress)
        } ?? nil
        
        guard let hPen = hPen else {
            // Fallback to simple pen
            let simplePen = CreatePen(PS_SOLID, width, RGB(0, 0, 0))
            guard let simplePen = simplePen else {
                throw WindowsError.fromLastError()
            }
            self.handle = PenHandle(simplePen) { pen in
                DeleteObject(HGDIOBJ(pen))
            }
            return
        }
        
        self.handle = PenHandleWrapper(hPen) { pen in
            DeleteObject(HGDIOBJ(pen))
        }
    }
}

/// Specialized handle wrapper for HPEN
public class PenHandleWrapper: Handle<HPEN> {
    public init(_ hPen: HPEN?, cleanup: @escaping (HPEN) -> Void) {
        super.init(hPen, cleanup: cleanup)
    }
}
#endif
import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Brush styles
#if canImport(WinSDK)
public enum BrushStyle: UInt32 {
    case solid = 0
    case null = 1
    case hatch = 2
    case pattern = 3
    case indexed = 4
    case dibPattern = 5
    case dibPatternPt = 6
    case pattern8x8 = 7
    case dibPattern8x8 = 8
    case monochromePattern = 9
}

/// Hatch styles for brushes
public enum HatchStyle: Int32 {
    case horizontal = 0
    case vertical = 1
    case forwardDiagonal = 2
    case backwardDiagonal = 3
    case cross = 4
    case diagonalCross = 5
}

/// Brush wrapper for GDI brush objects
public class Brush {
    private let handle: BrushHandleWrapper
    private let color: Color
    
    public var hBrush: HBRUSH? {
        return handle.handle
    }
    
    /// Create a solid brush
    public init(color: Color) throws {
        self.color = color
        
        let hBrush = CreateSolidBrush(color.colorRef)
        guard let hBrush = hBrush else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = BrushHandleWrapper(hBrush) { brush in
            DeleteObject(HGDIOBJ(brush))
        }
    }
    
    /// Create a hatched brush
    public init(color: Color, hatchStyle: HatchStyle) throws {
        self.color = color
        
        let hBrush = CreateHatchBrush(hatchStyle.rawValue, color.colorRef)
        guard let hBrush = hBrush else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = BrushHandleWrapper(hBrush) { brush in
            DeleteObject(HGDIOBJ(brush))
        }
    }
    
    /// Create a pattern brush from a bitmap
    public init(pattern: Bitmap) throws {
        guard let hBitmap = pattern.hBitmap else {
            throw WindowsError.invalidHandle
        }
        
        self.color = Color.black // Pattern brushes don't use a single color
        
        let hBrush = CreatePatternBrush(hBitmap)
        guard let hBrush = hBrush else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = BrushHandleWrapper(hBrush) { brush in
            DeleteObject(HGDIOBJ(brush))
        }
    }
    
    /// Create brush from a system color
    public init(systemColor: BackgroundBrush) {
        self.color = Color.black
        let hBrush = systemColor.hBrush
        self.handle = BrushHandleWrapper(hBrush) { _ in
            // System brushes should not be deleted
        }
    }
}

/// Specialized handle wrapper for HBRUSH
public class BrushHandleWrapper: Handle<HBRUSH> {
    public init(_ hBrush: HBRUSH?, cleanup: @escaping (HBRUSH) -> Void) {
        super.init(hBrush, cleanup: cleanup)
    }
}
#endif
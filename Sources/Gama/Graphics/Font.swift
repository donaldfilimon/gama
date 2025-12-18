import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Font weight constants
#if canImport(WinSDK)
public enum FontWeight: Int32 {
    case thin = 100
    case extraLight = 200
    case light = 300
    case normal = 400
    case medium = 500
    case semiBold = 600
    case bold = 700
    case extraBold = 800
    case heavy = 900
}

/// Font pitch and family
public enum FontPitch: UInt8 {
    case `default` = 0x00
    case fixed = 0x01
    case variable = 0x02
}

public enum FontFamily: UInt8 {
    case dontCare = 0x00
    case roman = 0x10
    case swiss = 0x20
    case modern = 0x30
    case script = 0x40
    case decorative = 0x50
}

/// Font wrapper for GDI font objects
public class Font {
    private let handle: FontHandleWrapper
    
    public var hFont: HFONT? {
        return handle.handle
    }
    
    /// Create a logical font
    public init(
        faceName: String,
        height: Int32,
        width: Int32 = 0,
        escapement: Int32 = 0,
        orientation: Int32 = 0,
        weight: FontWeight = .normal,
        italic: Bool = false,
        underline: Bool = false,
        strikeOut: Bool = false,
        charSet: UInt8 = DEFAULT_CHARSET,
        outputPrecision: UInt8 = OUT_DEFAULT_PRECIS,
        clipPrecision: UInt8 = CLIP_DEFAULT_PRECIS,
        quality: UInt8 = DEFAULT_QUALITY,
        pitchAndFamily: UInt8 = UInt8(FontPitch.default.rawValue) | UInt8(FontFamily.dontCare.rawValue)
    ) throws {
        var lf = LOGFONTW()
        lf.lfHeight = height
        lf.lfWidth = width
        lf.lfEscapement = escapement
        lf.lfOrientation = orientation
        lf.lfWeight = weight.rawValue
        lf.lfItalic = italic ? 1 : 0
        lf.lfUnderline = underline ? 1 : 0
        lf.lfStrikeOut = strikeOut ? 1 : 0
        lf.lfCharSet = charSet
        lf.lfOutPrecision = outputPrecision
        lf.lfClipPrecision = clipPrecision
        lf.lfQuality = quality
        lf.lfPitchAndFamily = pitchAndFamily
        
        // Copy face name
        faceName.withCString(encodedAs: UTF16.self) { namePtr in
            withUnsafeMutablePointer(to: &lf.lfFaceName) { faceNamePtr in
                let maxLen = min(31, faceName.utf16.count)
                for i in 0..<maxLen {
                    faceNamePtr.pointee.0[Int(i)] = namePtr[Int(i)]
                }
                faceNamePtr.pointee.0[Int(maxLen)] = 0
            }
        }
        
        let hFont = CreateFontIndirectW(&lf)
        guard let hFont = hFont else {
            throw WindowsError.fromLastError()
        }
        
        self.handle = FontHandle(hFont) { font in
            DeleteObject(HGDIOBJ(font))
        }
    }
    
    /// Create a font from a system font
    public static func systemFont(size: Int32 = -11) throws -> Font {
        // Default system font is typically Segoe UI
        return try Font(faceName: "Segoe UI", height: size)
    }
}

/// Specialized handle wrapper for HFONT
public class FontHandleWrapper: Handle<HFONT> {
    public init(_ hFont: HFONT?, cleanup: @escaping (HFONT) -> Void) {
        super.init(hFont, cleanup: cleanup)
    }
}
#endif
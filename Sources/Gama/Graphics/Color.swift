import Foundation
import WinSDK

// Color is defined in Core/Types.swift

/// Additional color constants
extension Color {
    public static let darkRed = Color(red: 139, green: 0, blue: 0)
    public static let darkGreen = Color(red: 0, green: 100, blue: 0)
    public static let darkBlue = Color(red: 0, green: 0, blue: 139)
    public static let yellow = Color(red: 255, green: 255, blue: 0)
    public static let magenta = Color(red: 255, green: 0, blue: 255)
    public static let cyan = Color(red: 0, green: 255, blue: 255)
    public static let gray = Color(red: 128, green: 128, blue: 128)
    public static let lightGray = Color(red: 192, green: 192, blue: 192)
    public static let darkGray = Color(red: 64, green: 64, blue: 64)
    public static let orange = Color(red: 255, green: 165, blue: 0)
    public static let purple = Color(red: 128, green: 0, blue: 128)
    public static let brown = Color(red: 165, green: 42, blue: 42)
    public static let pink = Color(red: 255, green: 192, blue: 203)
    
    /// Create color from RGB components (0.0-1.0 range)
    public init(redFloat: Double, greenFloat: Double, blueFloat: Double) {
        self.red = UInt8(redFloat * 255.0)
        self.green = UInt8(greenFloat * 255.0)
        self.blue = UInt8(blueFloat * 255.0)
    }
    
    /// Get RGB components as floats (0.0-1.0 range)
    public var floatComponents: (red: Double, green: Double, blue: Double) {
        return (
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0
        )
    }
    
    /// Create COLORREF (Windows color reference)
    public var colorRef: COLORREF {
        return COLORREF(rgb)
    }
}
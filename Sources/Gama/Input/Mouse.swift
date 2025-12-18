import Foundation
import WinSDK

/// Mouse input handling utilities
public struct Mouse {
    /// Get current cursor position in screen coordinates
    public static func getPosition() -> Point {
        var point = POINT()
        GetCursorPos(&point)
        return Point(point)
    }
    
    /// Set cursor position in screen coordinates
    public static func setPosition(_ point: Point) -> Bool {
        return SetCursorPos(point.x, point.y) != 0
    }
    
    /// Get cursor position relative to a window
    public static func getPosition(relativeTo window: Window) -> Point? {
        guard let hwnd = window.hwnd else { return nil }
        var point = POINT()
        guard ScreenToClient(hwnd, &point) != 0 else { return nil }
        return Point(point)
    }
    
    /// Check if a mouse button is currently pressed
    public static func isButtonDown(_ button: MouseButton) -> Bool {
        let vkey: Int32
        switch button {
        case .left: vkey = VK_LBUTTON
        case .right: vkey = VK_RBUTTON
        case .middle: vkey = VK_MBUTTON
        case .x1: vkey = VK_XBUTTON1
        case .x2: vkey = VK_XBUTTON2
        }
        return (GetAsyncKeyState(vkey) & 0x8000) != 0
    }
    
    /// Show or hide the cursor
    public static func showCursor(_ show: Bool) -> Int32 {
        return ShowCursor(show ? 1 : 0)
    }
    
    /// Clip cursor to a rectangle
    public static func clipCursor(to rect: Rectangle?) throws {
        if let rect = rect {
            var winRect = rect.win32Rect
            guard ClipCursor(&winRect) != 0 else {
                throw WindowsError.fromLastError()
            }
        } else {
            guard ClipCursor(nil) != 0 else {
                throw WindowsError.fromLastError()
            }
        }
    }
    
    /// Get the clip rectangle for the cursor
    public static func getClipRect() throws -> Rectangle {
        var rect = RECT()
        guard GetClipCursor(&rect) != 0 else {
            throw WindowsError.fromLastError()
        }
        return Rectangle(rect)
    }
}
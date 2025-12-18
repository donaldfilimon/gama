import Foundation
import WinSDK

/// Label/Static text control
public class Label: BaseControl {
    /// Static control styles
    public enum Style: DWORD {
        case left = 0x0000
        case center = 0x0001
        case right = 0x0002
        case icon = 0x0003
        case bitmap = 0x0004
        case simple = 0x000B
        case leftNoWrap = 0x000C
        case notify = 0x0100
        case centerImage = 0x0200
        case rightJust = 0x0400
        case realSizeImage = 0x0800
        case sunken = 0x1000
        case editControl = 0x2000
        case endEllipsis = 0x4000
        case pathEllipsis = 0x8000
        case wordEllipsis = 0x0C0000
        case noPrefix = 0x00800000
    }
    
    /// Create a label control
    public static func create(
        parent: Window,
        text: String,
        style: Style = .left,
        position: Point,
        size: Size,
        id: Int32 = 0
    ) throws -> Label {
        let className = "STATIC"
        let labelStyle: WindowStyleOptions = [
            .child, .visible
        ]
        
        let hwnd = className.withWindowsUTF16 { classNamePtr in
            text.withWindowsUTF16 { textPtr in
                CreateWindowExW(
                    0,
                    classNamePtr,
                    textPtr,
                    labelStyle.rawValue | style.rawValue,
                    position.x, position.y,
                    size.width, size.height,
                    parent.hwnd,
                    HMENU(bitPattern: UInt(id)),
                    GetModuleHandleW(nil),
                    nil
                )
            }
        }
        
        guard let hwnd = hwnd else {
            throw WindowsError.fromLastError()
        }
        
        let window = Window(handle: hwnd)
        return Label(window: window)
    }
    
    /// Initialize label from existing window
    public init(window: Window) {
        super.init(window: window)
    }
}
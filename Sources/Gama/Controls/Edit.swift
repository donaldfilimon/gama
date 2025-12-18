import Foundation
import WinSDK

/// Edit/Text control
public class Edit: BaseControl {
    /// Edit control styles
    public enum Style: DWORD {
        case left = 0x0000
        case center = 0x0001
        case right = 0x0002
        case multiline = 0x0004
        case upperCase = 0x0008
        case lowerCase = 0x0010
        case password = 0x0020
        case autoVScroll = 0x0040
        case autoHScroll = 0x0080
        case noHideSel = 0x0100
        case oemConvert = 0x0400
        case readOnly = 0x0800
        case wantReturn = 0x1000
        case number = 0x2000
    }
    
    /// Create an edit control
    public static func create(
        parent: Window,
        text: String = "",
        style: Style = .left,
        position: Point,
        size: Size,
        id: Int32 = 0
    ) throws -> Edit {
        let className = "EDIT"
        let editStyle: WindowStyleOptions = [
            .child, .visible, .border, .tabstop
        ]
        
        let hwnd = className.withWindowsUTF16 { classNamePtr in
            text.withWindowsUTF16 { textPtr in
                CreateWindowExW(
                    DWORD(WS_EX_CLIENTEDGE),
                    classNamePtr,
                    textPtr,
                    editStyle.rawValue | style.rawValue,
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
        return Edit(window: window)
    }
    
    /// Initialize edit from existing window
    public init(window: Window) {
        super.init(window: window)
    }
    
    /// Get the text content
    public var content: String {
        get {
            guard let hwnd = hwnd else { return "" }
            let length = SendMessageW(hwnd, UINT(WM_GETTEXTLENGTH), 0, 0)
            guard length > 0 else { return "" }
            
            let buffer = UnsafeMutablePointer<WCHAR>.allocate(capacity: Int(length) + 1)
            defer { buffer.deallocate() }
            SendMessageW(hwnd, UINT(WM_GETTEXT), WPARAM(length + 1), LPARAM(Int(bitPattern: buffer)))
            
            return String(windowsUTF16: buffer) ?? ""
        }
        set {
            text = newValue
        }
    }
    
    /// Set read-only mode
    public func setReadOnly(_ readOnly: Bool) {
        guard let hwnd = hwnd else { return }
        SendMessageW(hwnd, UINT(EM_SETREADONLY), readOnly ? 1 : 0, 0)
    }
}
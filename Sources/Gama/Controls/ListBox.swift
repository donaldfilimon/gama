import Foundation
import WinSDK

/// ListBox control
public class ListBox: BaseControl {
    /// ListBox styles
    public enum Style: DWORD {
        case notify = 0x0001
        case sort = 0x0002
        case noRedraw = 0x0004
        case multiSelect = 0x0008
        case useTabStops = 0x0080
        case noIntegralHeight = 0x0100
        case multiColumn = 0x0200
        case wantKeyInput = 0x0400
        case extendedSel = 0x0800
        case disableNoScroll = 0x1000
        case noData = 0x2000
        case comboBox = 0x8000
        case ownerDrawFixed = 0x0010
        case ownerDrawVariable = 0x0020
        case hasStrings = 0x0040
    }
    
    /// Create a list box control
    public static func create(
        parent: Window,
        style: Style = .notify,
        position: Point,
        size: Size,
        id: Int32 = 0
    ) throws -> ListBox {
        let className = "LISTBOX"
        let listBoxStyle: WindowStyleOptions = [
            .child, .visible, .border, .vscroll, .tabstop
        ]
        
        let hwnd = className.withWindowsUTF16 { classNamePtr in
            CreateWindowExW(
                DWORD(WS_EX_CLIENTEDGE),
                classNamePtr,
                nil,
                listBoxStyle.rawValue | style.rawValue,
                position.x, position.y,
                size.width, size.height,
                parent.hwnd,
                HMENU(bitPattern: UInt(id)),
                GetModuleHandleW(nil),
                nil
            )
        }
        
        guard let hwnd = hwnd else {
            throw WindowsError.fromLastError()
        }
        
        let window = Window(handle: hwnd)
        return ListBox(window: window)
    }
    
    /// Initialize list box from existing window
    public init(window: Window) {
        super.init(window: window)
    }
    
    /// Add an item to the list box
    public func addItem(_ text: String) -> Int32 {
        guard let hwnd = hwnd else { return -1 }
        return text.withWindowsUTF16 { textPtr in
            SendMessageW(hwnd, UINT(LB_ADDSTRING), 0, LPARAM(Int(bitPattern: textPtr)))
        }
    }
    
    /// Insert an item at a specific index
    public func insertItem(at index: Int32, text: String) -> Int32 {
        guard let hwnd = hwnd else { return -1 }
        return text.withWindowsUTF16 { textPtr in
            SendMessageW(hwnd, UINT(LB_INSERTSTRING), WPARAM(index), LPARAM(Int(bitPattern: textPtr)))
        }
    }
    
    /// Remove an item at index
    public func removeItem(at index: Int32) {
        guard let hwnd = hwnd else { return }
        SendMessageW(hwnd, UINT(LB_DELETESTRING), WPARAM(index), 0)
    }
    
    /// Clear all items
    public func clear() {
        guard let hwnd = hwnd else { return }
        SendMessageW(hwnd, UINT(LB_RESETCONTENT), 0, 0)
    }
    
    /// Get item count
    public var count: Int32 {
        guard let hwnd = hwnd else { return 0 }
        return SendMessageW(hwnd, UINT(LB_GETCOUNT), 0, 0)
    }
    
    /// Get selected item index
    public var selectedIndex: Int32 {
        get {
            guard let hwnd = hwnd else { return -1 }
            return SendMessageW(hwnd, UINT(LB_GETCURSEL), 0, 0)
        }
        set {
            guard let hwnd = hwnd else { return }
            SendMessageW(hwnd, UINT(LB_SETCURSEL), WPARAM(newValue), 0)
        }
    }
    
    /// Get item text at index
    public func item(at index: Int32) -> String {
        guard let hwnd = hwnd, index >= 0, index < count else { return "" }
        
        let length = SendMessageW(hwnd, UINT(LB_GETTEXTLEN), WPARAM(index), 0)
        guard length > 0 else { return "" }
        
        let buffer = UnsafeMutablePointer<WCHAR>.allocate(capacity: Int(length) + 1)
        defer { buffer.deallocate() }
        SendMessageW(hwnd, UINT(LB_GETTEXT), WPARAM(index), LPARAM(Int(bitPattern: buffer)))
        
        return String(windowsUTF16: buffer) ?? ""
    }
}
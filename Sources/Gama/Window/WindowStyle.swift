import Foundation
import WinSDK

/// Window style options builder
public struct WindowStyleOptions: OptionSet {
    public let rawValue: DWORD
    
    public init(rawValue: DWORD) {
        self.rawValue = rawValue
    }
    
    // Window styles
    public static let overlapped = WindowStyleOptions(rawValue: DWORD(WS_OVERLAPPED))
    public static let popup = WindowStyleOptions(rawValue: DWORD(WS_POPUP))
    public static let child = WindowStyleOptions(rawValue: DWORD(WS_CHILD))
    public static let minimize = WindowStyleOptions(rawValue: DWORD(WS_MINIMIZE))
    public static let visible = WindowStyleOptions(rawValue: DWORD(WS_VISIBLE))
    public static let disabled = WindowStyleOptions(rawValue: DWORD(WS_DISABLED))
    public static let clipsiblings = WindowStyleOptions(rawValue: DWORD(WS_CLIPSIBLINGS))
    public static let clipchildren = WindowStyleOptions(rawValue: DWORD(WS_CLIPCHILDREN))
    public static let maximize = WindowStyleOptions(rawValue: DWORD(WS_MAXIMIZE))
    public static let caption = WindowStyleOptions(rawValue: DWORD(WS_CAPTION))
    public static let border = WindowStyleOptions(rawValue: DWORD(WS_BORDER))
    public static let dlgframe = WindowStyleOptions(rawValue: DWORD(WS_DLGFRAME))
    public static let vscroll = WindowStyleOptions(rawValue: DWORD(WS_VSCROLL))
    public static let hscroll = WindowStyleOptions(rawValue: DWORD(WS_HSCROLL))
    public static let sysmenu = WindowStyleOptions(rawValue: DWORD(WS_SYSMENU))
    public static let thickframe = WindowStyleOptions(rawValue: DWORD(WS_THICKFRAME))
    public static let group = WindowStyleOptions(rawValue: DWORD(WS_GROUP))
    public static let tabstop = WindowStyleOptions(rawValue: DWORD(WS_TABSTOP))
    public static let minimizebox = WindowStyleOptions(rawValue: DWORD(WS_MINIMIZEBOX))
    public static let maximizebox = WindowStyleOptions(rawValue: DWORD(WS_MAXIMIZEBOX))
    
    /// Standard overlapped window style combination
    public static let overlappedWindow: WindowStyleOptions = [
        .caption, .sysmenu, .thickframe, .minimizebox, .maximizebox
    ]
    
    /// Standard popup window style combination
    public static let popupWindow: WindowStyleOptions = [
        .popup, .border, .sysmenu
    ]
}

// Extended window styles are now defined in WindowFactory.swift
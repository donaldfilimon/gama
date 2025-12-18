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

/// Extended window style options builder
public struct ExtendedWindowStyleOptions: OptionSet {
    public let rawValue: DWORD
    
    public init(rawValue: DWORD) {
        self.rawValue = rawValue
    }
    
    public static let dlgmodalframe = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_DLGMODALFRAME))
    public static let noparentnotify = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOPARENTNOTIFY))
    public static let topmost = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_TOPMOST))
    public static let acceptfiles = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_ACCEPTFILES))
    public static let transparent = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_TRANSPARENT))
    public static let mdiechild = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_MDICHILD))
    public static let toolwindow = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_TOOLWINDOW))
    public static let windowedge = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_WINDOWEDGE))
    public static let clientedge = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_CLIENTEDGE))
    public static let contexthelp = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_CONTEXTHELP))
    public static let right = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_RIGHT))
    public static let rtlreading = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_RTLREADING))
    public static let leftscrollbar = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_LEFTSCROLLBAR))
    public static let controlparent = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_CONTROLPARENT))
    public static let staticedge = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_STATICEDGE))
    public static let appwindow = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_APPWINDOW))
    public static let layere = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_LAYERED))
    public static let noinkinheritlayout = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOINHERITLAYOUT))
    public static let layoutefttoright = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_LAYOUTRTL))
    public static let noactivate = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOACTIVATE))
    public static let composited = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_COMPOSITED))
    public static let noRedirectionBitmap = ExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOREDIRECTIONBITMAP))
}
import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Windows-specific window style options builder
#if canImport(WinSDK)
public struct WindowsWindowStyleOptions: OptionSet {
    public let rawValue: DWORD

    public init(rawValue: DWORD) {
        self.rawValue = rawValue
    }

    // Window styles
    public static let overlapped = WindowsWindowStyleOptions(rawValue: DWORD(WS_OVERLAPPED))
    public static let popup = WindowsWindowStyleOptions(rawValue: DWORD(WS_POPUP))
    public static let child = WindowsWindowStyleOptions(rawValue: DWORD(WS_CHILD))
    public static let minimize = WindowsWindowStyleOptions(rawValue: DWORD(WS_MINIMIZE))
    public static let visible = WindowsWindowStyleOptions(rawValue: DWORD(WS_VISIBLE))
    public static let disabled = WindowsWindowStyleOptions(rawValue: DWORD(WS_DISABLED))
    public static let clipsiblings = WindowsWindowStyleOptions(rawValue: DWORD(WS_CLIPSIBLINGS))
    public static let clipchildren = WindowsWindowStyleOptions(rawValue: DWORD(WS_CLIPCHILDREN))
    public static let maximize = WindowsWindowStyleOptions(rawValue: DWORD(WS_MAXIMIZE))
    public static let caption = WindowsWindowStyleOptions(rawValue: DWORD(WS_CAPTION))
    public static let border = WindowsWindowStyleOptions(rawValue: DWORD(WS_BORDER))
    public static let dlgframe = WindowsWindowStyleOptions(rawValue: DWORD(WS_DLGFRAME))
    public static let vscroll = WindowsWindowStyleOptions(rawValue: DWORD(WS_VSCROLL))
    public static let hscroll = WindowsWindowStyleOptions(rawValue: DWORD(WS_HSCROLL))
    public static let sysmenu = WindowsWindowStyleOptions(rawValue: DWORD(WS_SYSMENU))
    public static let thickframe = WindowsWindowStyleOptions(rawValue: DWORD(WS_THICKFRAME))
    public static let group = WindowsWindowStyleOptions(rawValue: DWORD(WS_GROUP))
    public static let tabstop = WindowsWindowStyleOptions(rawValue: DWORD(WS_TABSTOP))
    public static let minimizebox = WindowsWindowStyleOptions(rawValue: DWORD(WS_MINIMIZEBOX))
    public static let maximizebox = WindowsWindowStyleOptions(rawValue: DWORD(WS_MAXIMIZEBOX))

    /// Standard overlapped window style combination
    public static let overlappedWindow: WindowsWindowStyleOptions = [
        .caption, .sysmenu, .thickframe, .minimizebox, .maximizebox
    ]

    /// Standard popup window style combination
    public static let popupWindow: WindowsWindowStyleOptions = [
        .popup, .border, .sysmenu
    ]
}

/// Windows-specific extended window style options builder
public struct WindowsExtendedWindowStyleOptions: OptionSet {
    public let rawValue: DWORD

    public init(rawValue: DWORD) {
        self.rawValue = rawValue
    }

    public static let dlgmodalframe = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_DLGMODALFRAME))
    public static let noparentnotify = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOPARENTNOTIFY))
    public static let topmost = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_TOPMOST))
    public static let acceptfiles = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_ACCEPTFILES))
    public static let transparent = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_TRANSPARENT))
    public static let mdiechild = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_MDICHILD))
    public static let toolwindow = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_TOOLWINDOW))
    public static let windowedge = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_WINDOWEDGE))
    public static let clientedge = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_CLIENTEDGE))
    public static let contexthelp = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_CONTEXTHELP))
    public static let right = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_RIGHT))
    public static let rtlreading = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_RTLREADING))
    public static let leftscrollbar = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_LEFTSCROLLBAR))
    public static let controlparent = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_CONTROLPARENT))
    public static let staticedge = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_STATICEDGE))
    public static let appwindow = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_APPWINDOW))
    public static let layere = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_LAYERED))
    public static let noinkinheritlayout = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOINHERITLAYOUT))
    public static let layoutefttoright = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_LAYOUTRTL))
    public static let noactivate = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOACTIVATE))
    public static let composited = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_COMPOSITED))
    public static let noRedirectionBitmap = WindowsExtendedWindowStyleOptions(rawValue: DWORD(WS_EX_NOREDIRECTIONBITMAP))
}
#endif
import Foundation
import WinSDK

/// Window style constants
public enum WindowStyle: DWORD {
    case overlapped = 0x00000000
    case popup = 0x80000000
    case child = 0x40000000
    case minimize = 0x20000000
    case visible = 0x10000000
    case disabled = 0x08000000
    case clipsiblings = 0x04000000
    case clipchildren = 0x02000000
    case maximize = 0x01000000
    case caption = 0x00C00000
    case border = 0x00800000
    case dlgframe = 0x00400000
    case vscroll = 0x00200000
    case hscroll = 0x00100000
    case sysmenu = 0x00080000
    case thickframe = 0x00040000
    case group = 0x00020000
    case tabstop = 0x00010000
    case minimizebox = 0x00020000
    case maximizebox = 0x00010000
    
    /// Standard overlapped window style
    public static let overlappedWindow: DWORD = 
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX
    
    /// Standard popup window style
    public static let popupWindow: DWORD = 
        WS_POPUP | WS_BORDER | WS_SYSMENU
}

/// Extended window style constants
public enum ExtendedWindowStyle: DWORD {
    case dlgmodalframe = 0x00000001
    case noparentnotify = 0x00000004
    case topmost = 0x00000008
    case acceptfiles = 0x00000010
    case transparent = 0x00000020
    case mdiechild = 0x00000040
    case toolwindow = 0x00000080
    case windowedge = 0x00000100
    case clientedge = 0x00000200
    case contexthelp = 0x00000400
    case right = 0x00001000
    case left = 0x00000000
    case rtlreading = 0x00002000
    case ltrreading = 0x00000000
    case leftscrollbar = 0x00004000
    case rightscrollbar = 0x00000000
    case controlparent = 0x00010000
    case staticedge = 0x00020000
    case appwindow = 0x00040000
    case layere = 0x00080000
    case norinkinheritlayout = 0x00100000
    case norinklayout = 0x00200000
    case layoutefttoright = 0x00400000
    case layoutighttoleft = 0x00800000
    case layourtop = 0x01000000
    case layoutrtl = 0x02000000
    case composited = 0x02000000
    case noactivate = 0x08000000
}

/// Window class style constants
public enum ClassStyle: UINT {
    case vredraw = 0x0001
    case hredraw = 0x0002
    case dblclks = 0x0008
    case ownDC = 0x0020
    case classDC = 0x0040
    case parentDC = 0x0080
    case noclose = 0x0200
    case savebits = 0x0800
    case bytealignclient = 0x1000
    case bytealignwindow = 0x2000
    case globalclass = 0x4000
    case ico = 0x00010000
    case doubles = 0x00020000
    
    public var rawValue: UINT {
        switch self {
        case .vredraw: return UINT(CS_VREDRAW)
        case .hredraw: return UINT(CS_HREDRAW)
        case .dblclks: return UINT(CS_DBLCLKS)
        case .ownDC: return UINT(CS_OWNDC)
        case .classDC: return UINT(CS_CLASSDC)
        case .parentDC: return UINT(CS_PARENTDC)
        case .noclose: return UINT(CS_NOCLOSE)
        case .savebits: return UINT(CS_SAVEBITS)
        case .bytealignclient: return UINT(CS_BYTEALIGNCLIENT)
        case .bytealignwindow: return UINT(CS_BYTEALIGNWINDOW)
        case .globalclass: return UINT(CS_GLOBALCLASS)
        case .ico: return UINT(CS_ICON)
        case .doubles: return UINT(CS_DBLCLKS)
        }
    }
}

/// Cursor resource IDs
public enum CursorID: Int32 {
    case arrow = 32512
    case ibeam = 32513
    case wait = 32514
    case cross = 32515
    case upArrow = 32516
    case size = 32640
    case icon = 32641
    case sizeNWSE = 32642
    case sizeNESW = 32643
    case sizeWE = 32644
    case sizeNS = 32645
    case sizeAll = 32646
    case no = 32648
    case hand = 32649
    case appStarting = 32650
    case help = 32651
}

/// Background brush constants
public enum BackgroundBrush: Int32 {
    case scrollbar = 0
    case desktop = 1
    case activeCaption = 2
    case inactiveCaption = 3
    case menu = 4
    case window = 5
    case windowFrame = 6
    case menuText = 7
    case windowText = 8
    case captionText = 9
    case activeBorder = 10
    case inactiveBorder = 11
    case appWorkSpace = 12
    case highlight = 13
    case highlightText = 14
    case buttonFace = 15
    case buttonShadow = 16
    case grayText = 17
    case buttonText = 18
    case inactiveCaptionText = 19
    case buttonHighlight = 20
    case darkShadow3D = 21
    case light3D = 22
    case infoText = 23
    case infoBackground = 24
    
    public var hBrush: HBRUSH {
        return HBRUSH(bitPattern: UInt(COLOR_WINDOW + Int32(rawValue)))
    }
}

/// Show window constants
public enum ShowWindowCommand: Int32 {
    case hide = 0
    case showNormal = 1
    case showMinimized = 2
    case showMaximized = 3
    case showNoActivate = 4
    case show = 5
    case minimize = 6
    case showMinNoActive = 7
    case showNA = 8
    case restore = 9
    case showDefault = 10
    case forceMinimize = 11
    
    public var rawValue: Int32 {
        switch self {
        case .hide: return SW_HIDE
        case .showNormal: return SW_SHOWNORMAL
        case .showMinimized: return SW_SHOWMINIMIZED
        case .showMaximized: return SW_SHOWMAXIMIZED
        case .showNoActivate: return SW_SHOWNOACTIVATE
        case .show: return SW_SHOW
        case .minimize: return SW_MINIMIZE
        case .showMinNoActive: return SW_SHOWMINNOACTIVE
        case .showNA: return SW_SHOWNA
        case .restore: return SW_RESTORE
        case .showDefault: return SW_SHOWDEFAULT
        case .forceMinimize: return SW_FORCEMINIMIZE
        }
    }
}

/// Message box type flags
public enum MessageBoxType: UINT {
    case ok = 0x00000000
    case okCancel = 0x00000001
    case abortRetryIgnore = 0x00000002
    case yesNoCancel = 0x00000003
    case yesNo = 0x00000004
    case retryCancel = 0x00000005
    case cancelTryContinue = 0x00000006
    case iconError = 0x00000010
    case iconQuestion = 0x00000020
    case iconWarning = 0x00000030
    case iconInformation = 0x00000040
    case defaultButton1 = 0x00000000
    case defaultButton2 = 0x00000100
    case defaultButton3 = 0x00000200
    case defaultButton4 = 0x00000300
    case applicationModal = 0x00000000
    case systemModal = 0x00001000
    case taskModal = 0x00002000
    case help = 0x00004000
    case noFocus = 0x00008000
    case setForeground = 0x00010000
    case defaultDesktopOnly = 0x00020000
    case topmost = 0x00040000
    case right = 0x00080000
    case rtlReading = 0x00100000
    
    public var rawValue: UINT {
        switch self {
        case .ok: return UINT(MB_OK)
        case .okCancel: return UINT(MB_OKCANCEL)
        case .abortRetryIgnore: return UINT(MB_ABORTRETRYIGNORE)
        case .yesNoCancel: return UINT(MB_YESNOCANCEL)
        case .yesNo: return UINT(MB_YESNO)
        case .retryCancel: return UINT(MB_RETRYCANCEL)
        case .cancelTryContinue: return UINT(MB_CANCELTRYCONTINUE)
        case .iconError: return UINT(MB_ICONERROR)
        case .iconQuestion: return UINT(MB_ICONQUESTION)
        case .iconWarning: return UINT(MB_ICONWARNING)
        case .iconInformation: return UINT(MB_ICONINFORMATION)
        default:
            return 0
        }
    }
}

/// Message box result
public enum MessageBoxResult: Int32 {
    case ok = 1
    case cancel = 2
    case abort = 3
    case retry = 4
    case ignore = 5
    case yes = 6
    case no = 7
    case tryAgain = 10
    case continue = 11
    
    public init?(rawValue: Int32) {
        switch rawValue {
        case IDOK: self = .ok
        case IDCANCEL: self = .cancel
        case IDABORT: self = .abort
        case IDRETRY: self = .retry
        case IDIGNORE: self = .ignore
        case IDYES: self = .yes
        case IDNO: self = .no
        case IDTRYAGAIN: self = .tryAgain
        case IDCONTINUE: self = .continue
        default: return nil
        }
    }
}
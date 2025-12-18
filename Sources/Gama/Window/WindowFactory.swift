import Foundation

/// Window factory for creating platform-specific window implementations
public class WindowFactory {
    /// Create a window with the appropriate platform implementation
    public static func createWindow(
        title: String,
        position: Point? = nil,
        size: Size? = nil,
        style: WindowStyleOptions = .overlappedWindow,
        parent: WindowProtocol? = nil
    ) throws -> WindowProtocol {
        try ensurePlatformSupport(for: "windowing", supported: hasWindowingSupport)

        #if os(Windows)
        return try WindowsWindow(
            title: title,
            position: position,
            size: size,
            style: WindowsWindowStyleOptions(rawValue: style.rawValue),
            parent: parent as? WindowsWindow
        )
        #elseif os(macOS) || os(iOS) || os(tvOS)
        return try AppleWindow(
            title: title,
            position: position,
            size: size,
            style: style,
            parent: parent as? AppleWindow
        )
        #elseif os(Linux)
        return try LinuxWindow(
            title: title,
            position: position,
            size: size,
            style: style,
            parent: parent as? LinuxWindow
        )
        #elseif os(Android)
        return try AndroidWindow(
            title: title,
            position: position,
            size: size,
            parent: parent as? AndroidWindow
        )
        #else
        throw PlatformError.operationFailed(reason: "Windowing not supported on platform '\(currentPlatform)'")
        #endif
    }

    /// Create a window from an existing native handle
    public static func createWindowFromHandle(_ handle: WindowHandle) -> WindowProtocol? {
        #if os(Windows)
        return WindowsWindow(handle: handle)
        #elseif os(macOS) || os(iOS) || os(tvOS)
        return AppleWindow(handle: handle)
        #elseif os(Linux)
        return LinuxWindow(handle: handle)
        #elseif os(Android)
        return AndroidWindow(handle: handle)
        #else
        return nil
        #endif
    }

    /// Get the platform-specific window class name
    public static var defaultWindowClassName: String {
        #if os(Windows)
        return "GamaWindow"
        #elseif os(macOS) || os(iOS) || os(tvOS)
        return "GamaAppleWindow"
        #elseif os(Linux)
        return "GamaLinuxWindow"
        #elseif os(Android)
        return "GamaAndroidWindow"
        #else
        return "GamaWindow"
        #endif
    }
}

/// Window style options (platform-agnostic)
public struct WindowStyleOptions: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // Common window styles
    public static let none = WindowStyleOptions(rawValue: 0)
    public static let overlapped = WindowStyleOptions(rawValue: 1 << 0)
    public static let popup = WindowStyleOptions(rawValue: 1 << 1)
    public static let child = WindowStyleOptions(rawValue: 1 << 2)
    public static let minimize = WindowStyleOptions(rawValue: 1 << 3)
    public static let visible = WindowStyleOptions(rawValue: 1 << 4)
    public static let disabled = WindowStyleOptions(rawValue: 1 << 5)
    public static let clipsiblings = WindowStyleOptions(rawValue: 1 << 6)
    public static let clipchildren = WindowStyleOptions(rawValue: 1 << 7)
    public static let maximize = WindowStyleOptions(rawValue: 1 << 8)
    public static let caption = WindowStyleOptions(rawValue: 1 << 9)
    public static let border = WindowStyleOptions(rawValue: 1 << 10)
    public static let dlgframe = WindowStyleOptions(rawValue: 1 << 11)
    public static let vscroll = WindowStyleOptions(rawValue: 1 << 12)
    public static let hscroll = WindowStyleOptions(rawValue: 1 << 13)
    public static let sysmenu = WindowStyleOptions(rawValue: 1 << 14)
    public static let thickframe = WindowStyleOptions(rawValue: 1 << 15)
    public static let group = WindowStyleOptions(rawValue: 1 << 16)
    public static let tabstop = WindowStyleOptions(rawValue: 1 << 17)
    public static let minimizebox = WindowStyleOptions(rawValue: 1 << 18)
    public static let maximizebox = WindowStyleOptions(rawValue: 1 << 19)

    /// Standard overlapped window style combination
    public static let overlappedWindow: WindowStyleOptions = [
        .caption, .sysmenu, .thickframe, .minimizebox, .maximizebox
    ]

    /// Standard popup window style combination
    public static let popupWindow: WindowStyleOptions = [
        .popup, .border, .sysmenu
    ]
}

/// Extended window style options (platform-agnostic)
public struct ExtendedWindowStyleOptions: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let dlgmodalframe = ExtendedWindowStyleOptions(rawValue: 1 << 0)
    public static let noparentnotify = ExtendedWindowStyleOptions(rawValue: 1 << 1)
    public static let topmost = ExtendedWindowStyleOptions(rawValue: 1 << 2)
    public static let acceptfiles = ExtendedWindowStyleOptions(rawValue: 1 << 3)
    public static let transparent = ExtendedWindowStyleOptions(rawValue: 1 << 4)
    public static let mdiechild = ExtendedWindowStyleOptions(rawValue: 1 << 5)
    public static let toolwindow = ExtendedWindowStyleOptions(rawValue: 1 << 6)
    public static let windowedge = ExtendedWindowStyleOptions(rawValue: 1 << 7)
    public static let clientedge = ExtendedWindowStyleOptions(rawValue: 1 << 8)
    public static let contexthelp = ExtendedWindowStyleOptions(rawValue: 1 << 9)
    public static let right = ExtendedWindowStyleOptions(rawValue: 1 << 10)
    public static let rtlreading = ExtendedWindowStyleOptions(rawValue: 1 << 11)
    public static let leftscrollbar = ExtendedWindowStyleOptions(rawValue: 1 << 12)
    public static let controlparent = ExtendedWindowStyleOptions(rawValue: 1 << 13)
    public static let staticedge = ExtendedWindowStyleOptions(rawValue: 1 << 14)
    public static let appwindow = ExtendedWindowStyleOptions(rawValue: 1 << 15)
    public static let layere = ExtendedWindowStyleOptions(rawValue: 1 << 16)
    public static let noinkinheritlayout = ExtendedWindowStyleOptions(rawValue: 1 << 17)
    public static let layoutefttoright = ExtendedWindowStyleOptions(rawValue: 1 << 18)
    public static let layourtop = ExtendedWindowStyleOptions(rawValue: 1 << 19)
    public static let layoutrtl = ExtendedWindowStyleOptions(rawValue: 1 << 20)
    public static let composited = ExtendedWindowStyleOptions(rawValue: 1 << 21)
    public static let noactivate = ExtendedWindowStyleOptions(rawValue: 1 << 22)
}
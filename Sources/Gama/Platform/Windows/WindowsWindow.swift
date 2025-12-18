import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Windows-specific window implementation
#if canImport(WinSDK)
public class WindowsWindow: WindowProtocol {
    private let handle: WindowHandle
    public weak var delegate: WindowDelegate?

    /// Global window registry for message routing
    private static var windowRegistry: [HWND: WindowsWindow] = [:]
    private static let registryLock = NSLock()

    /// Get the underlying HWND
    public var hwnd: HWND? {
        return handle.handle
    }

    /// Check if the window is valid
    public var isValid: Bool {
        guard let hwnd = handle.handle else { return false }
        return IsWindow(hwnd) != 0
    }

    /// Initialize with an existing HWND
    public init(handle: HWND) {
        self.handle = WindowHandle(handle)
        Self.registerWindow(handle: handle, window: self)
    }

    /// Create a new window
    public convenience init(
        title: String,
        position: Point? = nil,
        size: Size? = nil,
        style: WindowStyleOptions = .overlappedWindow,
        parent: WindowsWindow? = nil
    ) throws {
        let className = "GamaWindow"
        let x = position?.x ?? Int32(CW_USEDEFAULT)
        let y = position?.y ?? Int32(CW_USEDEFAULT)
        let width = size?.width ?? Int32(CW_USEDEFAULT)
        let height = size?.height ?? Int32(CW_USEDEFAULT)

        let hwnd = className.withWindowsUTF16 { classNamePtr in
            title.withWindowsUTF16 { titlePtr in
                CreateWindowExW(
                    0,
                    classNamePtr,
                    titlePtr,
                    style.rawValue,
                    x, y,
                    width, height,
                    parent?.hwnd,
                    nil,
                    GetModuleHandleW(nil),
                    nil
                )
            }
        }

        guard let hwnd = hwnd else {
            throw PlatformError.fromLastError()
        }

        self.init(handle: hwnd)
    }

    /// Register window for message routing
    private static func registerWindow(handle: HWND, window: WindowsWindow) {
        registryLock.lock()
        defer { registryLock.unlock() }
        windowRegistry[handle] = window
    }

    /// Unregister window
    private static func unregisterWindow(handle: HWND) {
        registryLock.lock()
        defer { registryLock.unlock() }
        windowRegistry.removeValue(forKey: handle)
    }

    /// Get window from HWND
    internal static func windowFromHandle(_ hwnd: HWND) -> WindowsWindow? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return windowRegistry[hwnd]
    }

    /// Window procedure for message handling
    internal static func windowProc(hwnd: HWND?, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT {
        guard let hwnd = hwnd else {
            return DefWindowProcW(hwnd, uMsg, wParam, lParam)
        }

        // Get window instance
        let window = windowFromHandle(hwnd)

        // Handle messages
        switch uMsg {
        case UINT(WM_DESTROY):
            window?.delegate?.windowWillDestroy(window!)
            PostQuitMessage(0)
            return 0

        case UINT(WM_CLOSE):
            if let window = window {
                if window.delegate?.windowWillClose(window) ?? true {
                    window.delegate?.windowDidClose(window)
                    DestroyWindow(hwnd)
                }
            } else {
                DestroyWindow(hwnd)
            }
            return 0

        case UINT(WM_SIZE):
            if let window = window {
                let width = LOWORD(DWORD(lParam.lowPart))
                let height = HIWORD(DWORD(lParam.lowPart))
                window.delegate?.windowDidResize(window, size: Size(width: Int32(width), height: Int32(height)))
            }
            return DefWindowProcW(hwnd, uMsg, wParam, lParam)

        case UINT(WM_MOVE):
            if let window = window {
                let x = Int32(Int16(LOWORD(DWORD(lParam.lowPart))))
                let y = Int32(Int16(HIWORD(DWORD(lParam.lowPart))))
                window.delegate?.windowDidMove(window, position: Point(x: x, y: y))
            }
            return DefWindowProcW(hwnd, uMsg, wParam, lParam)

        case UINT(WM_ACTIVATE):
            if let window = window {
                let active = LOWORD(DWORD(wParam.lowPart))
                if active != 0 {
                    window.delegate?.windowDidActivate(window)
                } else {
                    window.delegate?.windowDidDeactivate(window)
                }
            }
            return DefWindowProcW(hwnd, uMsg, wParam, lParam)

        case UINT(WM_PAINT):
            if let window = window {
                window.delegate?.windowWillPaint(window)
            }
            return DefWindowProcW(hwnd, uMsg, wParam, lParam)

        default:
            return DefWindowProcW(hwnd, uMsg, wParam, lParam)
        }
    }

    // MARK: - WindowProtocol Implementation

    public var title: String {
        get {
            guard let hwnd = handle.handle else { return "" }
            let length = GetWindowTextLengthW(hwnd)
            guard length > 0 else { return "" }

            let buffer = UnsafeMutablePointer<WCHAR>.allocate(capacity: Int(length) + 1)
            defer { buffer.deallocate() }
            GetWindowTextW(hwnd, buffer, Int32(length + 1))

            return String(windowsUTF16: buffer) ?? ""
        }
        set {
            guard let hwnd = handle.handle else { return }
            newValue.withWindowsUTF16 { titlePtr in
                SetWindowTextW(hwnd, titlePtr)
            }
        }
    }

    public var position: Point {
        get {
            guard let hwnd = handle.handle else { return Point(x: 0, y: 0) }
            var rect = RECT()
            GetWindowRect(hwnd, &rect)
            return Point(x: rect.left, y: rect.top)
        }
        set {
            guard let hwnd = handle.handle else { return }
            SetWindowPos(hwnd, nil, newValue.x, newValue.y, 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER))
        }
    }

    public var size: Size {
        get {
            guard let hwnd = handle.handle else { return Size(width: 0, height: 0) }
            var rect = RECT()
            GetWindowRect(hwnd, &rect)
            return Size(width: rect.right - rect.left, height: rect.bottom - rect.top)
        }
        set {
            guard let hwnd = handle.handle else { return }
            SetWindowPos(hwnd, nil, 0, 0, newValue.width, newValue.height, UINT(SWP_NOMOVE | SWP_NOZORDER))
        }
    }

    public var frame: Rectangle {
        get {
            guard let hwnd = handle.handle else { return Rectangle(left: 0, top: 0, right: 0, bottom: 0) }
            var rect = RECT()
            GetWindowRect(hwnd, &rect)
            return Rectangle(rect)
        }
        set {
            guard let hwnd = handle.handle else { return }
            SetWindowPos(hwnd, nil, newValue.left, newValue.top, newValue.width, newValue.height, UINT(SWP_NOZORDER))
        }
    }

    public var clientRect: Rectangle {
        guard let hwnd = handle.handle else {
            return Rectangle(left: 0, top: 0, right: 0, bottom: 0)
        }
        var rect = RECT()
        GetClientRect(hwnd, &rect)
        return Rectangle(rect)
    }

    public var isVisible: Bool {
        guard let hwnd = handle.handle else { return false }
        return IsWindowVisible(hwnd) != 0
    }

    public func show() {
        guard let hwnd = handle.handle else { return }
        ShowWindow(hwnd, SW_SHOW)
    }

    public func hide() {
        guard let hwnd = handle.handle else { return }
        ShowWindow(hwnd, SW_HIDE)
    }

    public func minimize() {
        guard let hwnd = handle.handle else { return }
        ShowWindow(hwnd, SW_MINIMIZE)
    }

    public func maximize() {
        guard let hwnd = handle.handle else { return }
        ShowWindow(hwnd, SW_MAXIMIZE)
    }

    public func restore() {
        guard let hwnd = handle.handle else { return }
        ShowWindow(hwnd, SW_RESTORE)
    }

    public func close() {
        guard let hwnd = handle.handle else { return }
        PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
    }

    public func update() {
        guard let hwnd = handle.handle else { return }
        UpdateWindow(hwnd)
    }

    public func focus() {
        guard let hwnd = handle.handle else { return }
        SetFocus(hwnd)
    }

    public func bringToFront() {
        guard let hwnd = handle.handle else { return }
        BringWindowToTop(hwnd)
    }

    public func sendToBack() {
        guard let hwnd = handle.handle else { return }
        SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE))
    }

    public func setDelegate(_ delegate: WindowDelegate?) {
        self.delegate = delegate
    }

    public func getDelegate() -> WindowDelegate? {
        return delegate
    }

    deinit {
        if let hwnd = handle.handle {
            Self.unregisterWindow(handle: hwnd)
        }
    }
}

// Helper functions for Windows macros
private func LOWORD(_ dword: DWORD) -> WORD {
    return WORD(dword & 0xFFFF)
}

private func HIWORD(_ dword: DWORD) -> WORD {
    return WORD((dword >> 16) & 0xFFFF)
}
#endif
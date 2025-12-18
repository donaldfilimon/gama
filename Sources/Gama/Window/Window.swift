import Foundation
import WinSDK

/// Window delegate protocol for handling window events
public protocol WindowDelegate: AnyObject {
    func windowWillClose(_ window: Window) -> Bool
    func windowDidClose(_ window: Window)
    func windowWillDestroy(_ window: Window)
    func windowDidResize(_ window: Window, size: Size)
    func windowDidMove(_ window: Window, position: Point)
    func windowDidActivate(_ window: Window)
    func windowDidDeactivate(_ window: Window)
    func windowWillPaint(_ window: Window)
}

/// Default implementation of WindowDelegate (all methods are optional)
public extension WindowDelegate {
    func windowWillClose(_ window: Window) -> Bool { return true }
    func windowDidClose(_ window: Window) {}
    func windowWillDestroy(_ window: Window) {}
    func windowDidResize(_ window: Window, size: Size) {}
    func windowDidMove(_ window: Window, position: Point) {}
    func windowDidActivate(_ window: Window) {}
    func windowDidDeactivate(_ window: Window) {}
    func windowWillPaint(_ window: Window) {}
}

/// High-level Window class wrapping HWND
public class Window {
    private let handle: WindowHandle
    public weak var delegate: WindowDelegate?
    
    /// Global window registry for message routing
    private static var windowRegistry: [HWND: Window] = [:]
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
        className: String,
        title: String,
        style: WindowStyleOptions = .overlappedWindow,
        extendedStyle: ExtendedWindowStyleOptions = [],
        position: Point? = nil,
        size: Size? = nil,
        parent: Window? = nil,
        menu: HMENU? = nil,
        hInstance: HMODULE? = nil
    ) throws {
        let instance = hInstance ?? GetModuleHandleW(nil)
        guard let instance = instance else {
            throw WindowsError.fromLastError()
        }
        
        let x = position?.x ?? Int32(CW_USEDEFAULT)
        let y = position?.y ?? Int32(CW_USEDEFAULT)
        let width = size?.width ?? Int32(CW_USEDEFAULT)
        let height = size?.height ?? Int32(CW_USEDEFAULT)
        
        let hwnd = className.withWindowsUTF16 { classNamePtr in
            title.withWindowsUTF16 { titlePtr in
                CreateWindowExW(
                    extendedStyle.rawValue,
                    classNamePtr,
                    titlePtr,
                    style.rawValue,
                    x, y,
                    width, height,
                    parent?.hwnd,
                    menu,
                    instance,
                    nil
                )
            }
        }
        
        guard let hwnd = hwnd else {
            throw WindowsError.fromLastError()
        }
        
        self.init(handle: hwnd)
    }
    
    /// Register window for message routing
    private static func registerWindow(handle: HWND, window: Window) {
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
    internal static func windowFromHandle(_ hwnd: HWND) -> Window? {
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
            
        case UINT(WM_TIMER):
            // Handle timer callbacks
            Timer.handleTimer(timerId: UIntPtr(bitPattern: Int(wParam.lowPart)))
            return 0
            
        default:
            return DefWindowProcW(hwnd, uMsg, wParam, lParam)
        }
    }
    
    /// Show the window
    public func show(command: ShowWindowCommand = .showNormal) {
        guard let hwnd = handle.handle else { return }
        ShowWindow(hwnd, command.rawValue)
    }
    
    /// Hide the window
    public func hide() {
        show(command: .hide)
    }
    
    /// Update the window (force redraw)
    public func update() {
        guard let hwnd = handle.handle else { return }
        UpdateWindow(hwnd)
    }
    
    /// Close the window
    public func close() {
        guard let hwnd = handle.handle else { return }
        PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
    }
    
    /// Destroy the window
    public func destroy() {
        guard let hwnd = handle.handle else { return }
        Self.unregisterWindow(handle: hwnd)
        DestroyWindow(hwnd)
        handle.release()
    }
    
    /// Get window title
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
    
    /// Get window position
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
    
    /// Get window size
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
    
    /// Get client area rectangle
    public var clientRect: Rectangle {
        guard let hwnd = handle.handle else {
            return Rectangle(left: 0, top: 0, right: 0, bottom: 0)
        }
        var rect = RECT()
        GetClientRect(hwnd, &rect)
        return Rectangle(rect)
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
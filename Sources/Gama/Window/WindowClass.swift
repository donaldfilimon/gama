import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Window class registration wrapper
#if canImport(WinSDK)
public class WindowClass {
    private var className: String
    private var windowProc: WNDPROC?
    private var isRegistered = false
    
    public var name: String {
        return className
    }
    
    /// Initialize a window class with a name
    public init(name: String) {
        self.className = name
    }
    
    /// Register the window class with Windows
    public func register(
        style: ClassStyleOptions = .default,
        windowProc: @escaping WNDPROC,
        hInstance: HMODULE? = nil,
        hCursor: HCURSOR? = nil,
        hBrush: HBRUSH? = nil,
        hIcon: HICON? = nil,
        menuName: String? = nil
    ) throws {
        guard !isRegistered else {
            throw WindowsError.operationFailed(reason: "Window class already registered")
        }
        
        let instance = hInstance ?? GetModuleHandleW(nil)
        guard let instance = instance else {
            throw WindowsError.fromLastError()
        }
        
        self.windowProc = windowProc
        
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.style = style.rawValue
        wc.lpfnWndProc = windowProc
        wc.hInstance = instance
        wc.hCursor = hCursor ?? LoadCursorW(nil, UnsafePointer<UInt16>(bitPattern: Int(CursorID.arrow.rawValue)))
        wc.hbrBackground = hBrush ?? BackgroundBrush.window.hBrush
        wc.lpszClassName = className.withWindowsUTF16 { $0 }
        
        if let hIcon = hIcon {
            wc.hIcon = hIcon
        }
        
        if let menuName = menuName {
            wc.lpszMenuName = menuName.withWindowsUTF16 { $0 }
        }
        
        let atom = RegisterClassExW(&wc)
        guard atom != 0 else {
            let error = GetLastError()
            if error != ERROR_CLASS_ALREADY_EXISTS {
                throw WindowsError.fromErrorCode(error)
            }
        }
        
        isRegistered = true
    }
    
    /// Unregister the window class
    public func unregister(hInstance: HMODULE? = nil) throws {
        guard isRegistered else { return }
        
        let instance = hInstance ?? GetModuleHandleW(nil)
        guard let instance = instance else {
            throw WindowsError.fromLastError()
        }
        
        className.withWindowsUTF16 { classNamePtr in
            UnregisterClassW(classNamePtr, instance)
        }
        
        isRegistered = false
    }
    
    deinit {
        if isRegistered {
            try? unregister()
        }
    }
}

/// Class style options builder
public struct ClassStyleOptions: OptionSet {
    public let rawValue: UINT
    
    public init(rawValue: UINT) {
        self.rawValue = rawValue
    }
    
    public static let vredraw = ClassStyleOptions(rawValue: UINT(CS_VREDRAW))
    public static let hredraw = ClassStyleOptions(rawValue: UINT(CS_HREDRAW))
    public static let dblclks = ClassStyleOptions(rawValue: UINT(CS_DBLCLKS))
    public static let ownDC = ClassStyleOptions(rawValue: UINT(CS_OWNDC))
    public static let classDC = ClassStyleOptions(rawValue: UINT(CS_CLASSDC))
    public static let parentDC = ClassStyleOptions(rawValue: UINT(CS_PARENTDC))
    public static let noclose = ClassStyleOptions(rawValue: UINT(CS_NOCLOSE))
    public static let savebits = ClassStyleOptions(rawValue: UINT(CS_SAVEBITS))
    public static let bytealignclient = ClassStyleOptions(rawValue: UINT(CS_BYTEALIGNCLIENT))
    public static let bytealignwindow = ClassStyleOptions(rawValue: UINT(CS_BYTEALIGNWINDOW))
    public static let globalclass = ClassStyleOptions(rawValue: UINT(CS_GLOBALCLASS))
    public static let ico = ClassStyleOptions(rawValue: UINT(CS_ICON))
    
    public static let `default`: ClassStyleOptions = [.vredraw, .hredraw]
}
#endif
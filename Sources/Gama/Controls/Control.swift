import Foundation
import WinSDK

/// Base protocol for all controls
public protocol Control {
    var window: Window { get }
    var hwnd: HWND? { get }
}

/// Base control class
public class BaseControl: Control {
    public let window: Window
    
    public var hwnd: HWND? {
        return window.hwnd
    }
    
    public init(window: Window) {
        self.window = window
    }
    
    /// Enable or disable the control
    public func setEnabled(_ enabled: Bool) {
        guard let hwnd = hwnd else { return }
        EnableWindow(hwnd, enabled ? 1 : 0)
    }
    
    /// Check if the control is enabled
    public var isEnabled: Bool {
        guard let hwnd = hwnd else { return false }
        return IsWindowEnabled(hwnd) != 0
    }
    
    /// Show or hide the control
    public func setVisible(_ visible: Bool) {
        window.show(command: visible ? .show : .hide)
    }
    
    /// Check if the control is visible
    public var isVisible: Bool {
        guard let hwnd = hwnd else { return false }
        return IsWindowVisible(hwnd) != 0
    }
    
    /// Get or set the control text
    public var text: String {
        get {
            return window.title
        }
        set {
            window.title = newValue
        }
    }
    
    /// Get control position
    public var position: Point {
        get {
            guard let hwnd = hwnd else { return Point(x: 0, y: 0) }
            var rect = RECT()
            GetWindowRect(hwnd, &rect)
            return Point(x: rect.left, y: rect.top)
        }
        set {
            guard let hwnd = hwnd else { return }
            var rect = RECT()
            GetWindowRect(hwnd, &rect)
            let width = rect.right - rect.left
            let height = rect.bottom - rect.top
            SetWindowPos(hwnd, nil, newValue.x, newValue.y, width, height, UINT(SWP_NOZORDER))
        }
    }
    
    /// Get control size
    public var size: Size {
        get {
            guard let hwnd = hwnd else { return Size(width: 0, height: 0) }
            var rect = RECT()
            GetWindowRect(hwnd, &rect)
            return Size(width: rect.right - rect.left, height: rect.bottom - rect.top)
        }
        set {
            guard let hwnd = hwnd else { return }
            var rect = RECT()
            GetWindowRect(hwnd, &rect)
            SetWindowPos(hwnd, nil, rect.left, rect.top, newValue.width, newValue.height, UINT(SWP_NOMOVE | SWP_NOZORDER))
        }
    }
}
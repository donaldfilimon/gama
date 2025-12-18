import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Timer callback type
public typealias TimerCallback = () -> Void

/// Platform-specific window timer wrapper
/// Note: This is a Windows-specific implementation. For cross-platform timers,
/// use the Timer in System/Timer.swift which uses async/await.
#if canImport(WinSDK)
public class WindowTimer {
    private static var timerCallbacks: [UIntPtr: TimerCallback] = [:]
    private static let callbackLock = NSLock()
    private let timerId: UIntPtr
    private var callback: TimerCallback?
    private var window: Window?
    
    /// Create a timer associated with a window
    public init(window: Window, interval: UINT, callback: @escaping TimerCallback) throws {
        // Access platform-specific window handle
        guard let windowsWindow = window.platformWindow as? WindowsWindow,
              let hwnd = windowsWindow.hwnd else {
            throw PlatformError.invalidHandle
        }
        
        // Generate unique timer ID
        self.timerId = UIntPtr(bitPattern: ObjectIdentifier(self))
        self.callback = callback
        self.window = window
        
        // Register callback
        Self.callbackLock.lock()
        defer { Self.callbackLock.unlock() }
        Self.timerCallbacks[timerId] = callback
        
        // Set timer - Windows will send WM_TIMER messages
        // We need to handle this in the window procedure instead
        guard SetTimer(hwnd, timerId, interval, nil) != 0 else {
            Self.callbackLock.lock()
            Self.timerCallbacks.removeValue(forKey: timerId)
            Self.callbackLock.unlock()
            throw PlatformError.fromLastError()
        }
    }
    
    /// Handle timer callback from Windows (called from Window message handler)
    internal static func handleTimer(timerId: UIntPtr) {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        
        if let callback = timerCallbacks[timerId] {
            callback()
        }
    }
    
    /// Kill the timer
    public func kill() {
        guard let window = window,
              let windowsWindow = window.platformWindow as? WindowsWindow,
              let hwnd = windowsWindow.hwnd else { return }
        
        KillTimer(hwnd, timerId)
        
        Self.callbackLock.lock()
        Self.timerCallbacks.removeValue(forKey: timerId)
        Self.callbackLock.unlock()
        
        callback = nil
        window = nil
    }
    
    deinit {
        kill()
    }
}

/// Legacy type alias for compatibility
// Note: Use WindowTimer directly instead of the Timer typealias to avoid conflicts
#else
/// Window timer is not available on non-Windows platforms
/// Use System.Timer for cross-platform timer functionality
public enum WindowTimerError: Error {
    case notAvailableOnThisPlatform
}

public class WindowTimer {
    public init(window: Window, interval: UInt32, callback: @escaping TimerCallback) throws {
        throw WindowTimerError.notAvailableOnThisPlatform
    }
    
    public func kill() {
        // No-op on non-Windows platforms
    }
}
#endif
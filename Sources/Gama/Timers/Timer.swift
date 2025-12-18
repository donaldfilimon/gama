import Foundation
import WinSDK

/// Timer callback type
public typealias TimerCallback = () -> Void

/// Timer wrapper
public class Timer {
    private static var timerCallbacks: [UIntPtr: TimerCallback] = [:]
    private static let callbackLock = NSLock()
    private let timerId: UIntPtr
    private var callback: TimerCallback?
    private var window: Window?
    
    /// Create a timer associated with a window
    public init(window: Window, interval: UINT, callback: @escaping TimerCallback) throws {
        guard let hwnd = window.hwnd else {
            throw WindowsError.invalidHandle
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
            throw WindowsError.fromLastError()
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
        guard let hwnd = window?.hwnd else { return }
        
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
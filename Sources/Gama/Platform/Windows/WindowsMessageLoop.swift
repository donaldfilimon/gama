import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Windows-specific window message loop manager
#if canImport(WinSDK)
public class WindowsMessageLoop {
    private var isRunning = false

    public init() {}

    /// Run the message loop (blocks until quit)
    public func run() -> Int32 {
        isRunning = true

        var msg = MSG()
        var result: Int32 = 0

        while GetMessageW(&msg, nil, 0, 0) != 0 {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }

        result = msg.wParam.lowPart
        isRunning = false
        return result
    }

    /// Peek and process messages without blocking
    /// Returns true if a message was processed
    public func peekAndProcess() -> Bool {
        var msg = MSG()
        guard PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) != 0 else {
            return false
        }

        TranslateMessage(&msg)
        DispatchMessageW(&msg)

        if msg.message == UINT(WM_QUIT) {
            isRunning = false
        }

        return true
    }

    /// Process pending messages (non-blocking)
    public func processPendingMessages() {
        var msg = MSG()
        while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) != 0 {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)

            if msg.message == UINT(WM_QUIT) {
                isRunning = false
                break
            }
        }
    }

    /// Post a quit message to the message queue
    public func quit(exitCode: Int32 = 0) {
        PostQuitMessage(exitCode)
        isRunning = false
    }

    /// Check if the message loop is currently running
    public var running: Bool {
        return isRunning
    }
}

/// Message peek options
public enum PeekMessageOptions: UINT {
    case remove = 0x0001
    case noRemove = 0x0000
    case noYield = 0x0002

    public var rawValue: UINT {
        switch self {
        case .remove: return UINT(PM_REMOVE)
        case .noRemove: return UINT(PM_NOREMOVE)
        case .noYield: return UINT(PM_NOYIELD)
        }
    }
}
#endif
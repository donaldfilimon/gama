import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Protocol for platform-specific message loop implementations
public protocol MessageLoopProtocol {
    func run() -> Int32
    func peekAndProcess() -> Bool
    func processPendingMessages()
    func quit(exitCode: Int32)
    var running: Bool { get }
}

/// Cross-platform window message loop manager
/// Uses platform-specific implementations via factory pattern
public class MessageLoop: MessageLoopProtocol {
    private let platformLoop: MessageLoopProtocol
    
    public init() {
        #if os(Windows)
        self.platformLoop = WindowsMessageLoop()
        #elseif os(macOS) || os(iOS) || os(tvOS)
        // Apple message loop (stub - to be implemented)
        fatalError("MessageLoop not yet implemented for Apple platforms")
        #elseif os(Linux)
        // Linux message loop (stub - to be implemented)
        fatalError("MessageLoop not yet implemented for Linux")
        #elseif os(Android)
        // Android message loop (stub - to be implemented)
        fatalError("MessageLoop not yet implemented for Android")
        #else
        fatalError("MessageLoop not supported on platform: \(currentPlatform)")
        #endif
    }
    
    /// Run the message loop (blocks until quit)
    public func run() -> Int32 {
        return platformLoop.run()
    }
    
    /// Peek and process messages without blocking
    /// Returns true if a message was processed
    public func peekAndProcess() -> Bool {
        return platformLoop.peekAndProcess()
    }
    
    /// Process pending messages (non-blocking)
    public func processPendingMessages() {
        platformLoop.processPendingMessages()
    }
    
    /// Post a quit message to the message queue
    public func quit(exitCode: Int32 = 0) {
        platformLoop.quit(exitCode: exitCode)
    }
    
    /// Check if the message loop is currently running
    public var running: Bool {
        return platformLoop.running
    }
}

#if canImport(WinSDK)
/// Message peek options (Windows-specific)
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
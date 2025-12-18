import Foundation

/// A frame scheduler inspired by browser `requestAnimationFrame`.
///
/// Manages frame-based rendering with VSync synchronization and automatic
/// frame skipping for performance.
///
/// Swift 6.2: Enhanced with region-based isolation and improved concurrency
@MainActor
public final class FrameScheduler: @unchecked Sendable {
    private var frameCallbacks: [FrameCallback] = []
    private var isRunning = false
    private var frameTask: Task<Void, Never>?
    private let lock = NSLock()
    
    /// Target frame rate (frames per second)
    public var targetFPS: Double = 60.0 {
        didSet {
            frameInterval = 1.0 / targetFPS
        }
    }
    
    private var frameInterval: TimeInterval = 1.0 / 60.0
    
    /// Creates a frame scheduler.
    public init(targetFPS: Double = 60.0) {
        self.targetFPS = targetFPS
        self.frameInterval = 1.0 / targetFPS
    }
    
    /// Requests a callback for the next frame.
    ///
    /// - Parameter callback: The callback to invoke on the next frame.
    /// - Returns: A cancellation token that can be used to cancel the callback.
    public func requestFrame(callback: @escaping @MainActor (TimeInterval) -> Void) -> CancellationToken {
        let token = CancellationToken()
        let frameCallback = FrameCallback(id: token.id, callback: callback)
        
        lock.lock()
        frameCallbacks.append(frameCallback)
        lock.unlock()
        
        // Start the frame loop if not running
        if !isRunning {
            startFrameLoop()
        }
        
        return token
    }
    
    /// Cancels a frame callback.
    ///
    /// - Parameter token: The cancellation token returned from `requestFrame`.
    public func cancelFrame(_ token: CancellationToken) {
        lock.lock()
        frameCallbacks.removeAll { $0.id == token.id }
        lock.unlock()
    }
    
    /// Starts the frame loop.
    private func startFrameLoop() {
        guard !isRunning else { return }
        isRunning = true
        
        frameTask = Task { @MainActor in
            var lastFrameTime = Date()
            
            while isRunning {
                let frameStartTime = Date()
                let deltaTime = frameStartTime.timeIntervalSince(lastFrameTime)
                lastFrameTime = frameStartTime
                
                // Execute frame callbacks
                lock.lock()
                let callbacks = frameCallbacks
                lock.unlock()
                
                for callback in callbacks {
                    callback.callback(deltaTime)
                }
                
                // Remove cancelled callbacks
                lock.lock()
                frameCallbacks.removeAll { $0.isCancelled }
                lock.unlock()
                
                // Sleep until next frame (VSync simulation)
                let frameTime = Date().timeIntervalSince(frameStartTime)
                let sleepTime = max(0, frameInterval - frameTime)
                
                if sleepTime > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
                }
                
                // Stop if no more callbacks
                lock.lock()
                if frameCallbacks.isEmpty {
                    isRunning = false
                    lock.unlock()
                    break
                }
                lock.unlock()
            }
        }
    }
    
    /// Stops the frame loop.
    public func stop() {
        isRunning = false
        frameTask?.cancel()
        frameTask = nil
        
        lock.lock()
        frameCallbacks.removeAll()
        lock.unlock()
    }
    
    deinit {
        stop()
    }
}

/// A frame callback
private struct FrameCallback: Sendable {
    let id: UUID
    let callback: @MainActor @Sendable (TimeInterval) -> Void
    var isCancelled: Bool = false
}

/// A cancellation token for frame callbacks
public struct CancellationToken: Sendable {
    let id: UUID
    
    public init() {
        self.id = UUID()
    }
}
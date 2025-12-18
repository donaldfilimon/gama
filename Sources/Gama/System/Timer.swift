import Foundation

/// A unified timer that provides async/await support.
///
/// This provides a platform-agnostic interface for timers using Swift 6
/// structured concurrency.
///
/// Swift 6.2: Enhanced with region-based isolation
public actor Timer: @unchecked Sendable {
    /// Creates a timer that fires after a specified interval.
    ///
    /// - Parameters:
    ///   - interval: The time interval in seconds.
    ///   - repeats: Whether the timer should repeat.
    /// - Returns: An async sequence that yields the current date.
    public static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool) -> AsyncStream<Date> {
        AsyncStream { continuation in
            let timer = Foundation.Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { timer in
                continuation.yield(Date())
                if !repeats {
                    continuation.finish()
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                timer.invalidate()
            }
        }
    }
    
    /// Sleeps for a specified duration.
    ///
    /// - Parameter duration: The duration to sleep in seconds.
    public static func sleep(for duration: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
    
    /// Creates a timer that fires once after a delay.
    ///
    /// - Parameter delay: The delay in seconds.
    /// - Returns: A task that completes after the delay.
    public static func delayed(by delay: TimeInterval) async {
        await sleep(for: delay)
    }
}

/// A repeating timer that can be started and stopped.
///
/// Swift 6.2: Enhanced with improved concurrency safety
@MainActor
public final class RepeatingTimer: @unchecked Sendable {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval
    private let action: @Sendable () -> Void
    
    /// Creates a repeating timer.
    ///
    /// - Parameters:
    ///   - interval: The time interval between timer firings.
    ///   - action: The action to perform on each timer fire.
    public init(interval: TimeInterval, action: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.action = action
    }
    
    /// Starts the timer.
    public func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    /// Stops the timer.
    public func stop() {
        task?.cancel()
        task = nil
    }
    
    deinit {
        stop()
    }
}
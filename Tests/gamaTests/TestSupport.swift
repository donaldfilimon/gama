//  TestSupport.swift — helpers shared by the Swift Testing suites.

/// Mutable box for observer callbacks. Tests may import Synchronization;
/// GamaCore cannot. This keeps `@Sendable` closures compiling without
/// `nonisolated(unsafe)` counters.
final class TestBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

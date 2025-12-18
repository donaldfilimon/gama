import Foundation

/// Swift 6.2: Typed error handling utilities
/// These provide enhanced error handling using Swift 6.2 typed throws

/// Swift 6.2: Helper for typed error handling
/// Wraps an operation that throws a specific error type
@inlinable
public func tryOrThrow<T, E: Error>(
    _ operation: () throws(E) -> T
) throws(E) -> T {
    try operation()
}

/// Swift 6.2: Platform-specific error handling
/// Converts platform errors to Result type
@inlinable
public func tryPlatform<T>(
    _ operation: () throws -> T
) -> Result<T, PlatformError> {
    do {
        return .success(try operation())
    } catch let error as PlatformError {
        return .failure(error)
    } catch {
        return .failure(.operationFailed(reason: String(describing: error)))
    }
}

/// Swift 6.2: Typed error conversion helper
@inlinable
public func mapError<T, E: Error, F: Error>(
    _ result: Result<T, E>,
    _ transform: (E) -> F
) -> Result<T, F> {
    result.mapError(transform)
}

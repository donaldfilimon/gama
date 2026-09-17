//  FailureExitCode.swift — GamaCore
//  A validated nonzero byte-sized failure code for process-facing
//  application results. Construction accepts only 1...255 so a
//  conventional eight-bit process status cannot observe a "failure"
//  as zero. The application still owns exit.

/// A nonzero byte-sized failure code for process-facing application results.
///
/// Use this value when a failure must remain nonzero at a conventional
/// eight-bit process-status boundary. Construction accepts only `1...255`.
/// It rejects zero, negative values, and larger integers; it never truncates
/// or silently changes a caller's code. The application still owns exit.
///
/// This type does not reserve shell-specific meanings or encode signals.
/// Prefer ``general`` for an ordinary error. Applications choosing other
/// values must document their exit-code policy.
public struct FailureExitCode: RawRepresentable, Hashable, Sendable {
    /// The validated nonzero value. It cannot be changed after construction.
    public let rawValue: Int32

    /// Creates a failure code only when `rawValue` is in `1...255`.
    ///
    /// - Parameter rawValue: The requested process-facing failure code.
    /// - Returns: `nil` when the value is zero or outside the byte range.
    public init?(rawValue: Int32) {
        guard rawValue >= 1 && rawValue <= 255 else { return nil }
        self.rawValue = rawValue
    }

    // Only the known-valid constant below uses this initializer.
    private init(validatedValue: Int32) {
        self.rawValue = validatedValue
    }

    /// The conventional general application failure code, `1`.
    public static let general = FailureExitCode(validatedValue: 1)
}

extension CompletionStatus {
    /// Creates an initially failing status from a validated process exit code.
    ///
    /// This additive overload leaves `failure(code:_:)`, the raw initializer,
    /// and the existing mutable `code` property unchanged. A caller can still
    /// mutate the returned status; the guarantee applies at construction.
    ///
    /// - Parameters:
    ///   - exitCode: A validated nonzero code in `1...255`.
    ///   - message: Optional diagnostic detail, not machine-readable output.
    /// - Returns: A status whose `isSuccess` is initially `false`.
    public static func failure(
        exitCode: FailureExitCode,
        _ message: String? = nil
    ) -> CompletionStatus {
        CompletionStatus(code: exitCode.rawValue, message: message)
    }
}

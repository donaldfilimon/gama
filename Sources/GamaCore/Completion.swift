//  Completion.swift — GamaCore
//  A retained UI is state over time; a process is an event with an
//  outcome. Backends that must terminate — a non-interactive terminal
//  run, a headless render — need the application to say when it is
//  finished and what to report. Quiescence cannot answer that: an idle
//  host is indistinguishable from a successful one, so failure would be
//  unreportable. The status is therefore declared, never inferred.
//  Int32 and String are stdlib types, so the stdlib-only boundary holds.

/// The outcome an application reports when its work is done.
///
/// `code` is carried as `Int32` because that is the width a process exit
/// status is ultimately narrowed to; GamaCore itself never exits a
/// process, and translating this into one is a backend's job.
public struct CompletionStatus: Hashable, Sendable {
    /// The reportable outcome, where zero means success by POSIX convention.
    public var code: Int32
    /// Optional human-readable detail a backend may surface, typically on
    /// stderr. Never part of the machine-readable outcome.
    public var message: String?

    /// Creates a status from an explicit code and optional detail.
    public init(code: Int32, message: String? = nil) {
        self.code = code
        self.message = message
    }

    /// The successful outcome: code zero, no detail.
    public static let success = CompletionStatus(code: 0, message: nil)

    /// Creates a failing outcome. A zero `code` is accepted rather than
    /// trapped, but `isSuccess` then reports `true`, so callers that mean
    /// failure must pass a non-zero code.
    public static func failure(code: Int32, _ message: String? = nil) -> CompletionStatus {
        CompletionStatus(code: code, message: message)
    }

    /// True when this status reports success.
    public var isSuccess: Bool { code == 0 }
}

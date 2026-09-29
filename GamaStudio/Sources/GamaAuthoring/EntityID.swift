/// The identity of one authored entity.
///
/// Identifiers are allocated by the owning ``SceneDocument`` from a monotonic
/// counter and are never reused, not even after the entity is deleted or its
/// creation is undone. They are deterministic, so the same sequence of commands
/// always produces the same identifiers (ADR 0001).
public struct EntityID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// The allocator's value for this identity. Zero is never allocated.
    public let rawValue: UInt64

    /// Wraps a raw value, for decoding and tests. Allocation goes through
    /// ``SceneDocument/nextEntityID``.
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { "#\(rawValue)" }
}

/// The set of selected entities, in selection order, with one primary.
///
/// Selection is editor state, not authored state (ADR 0001): it is not part of
/// undo history, and ``EditorSession`` prunes it whenever entities disappear.
public struct Selection: Hashable, Sendable {
    /// Selected entities in the order they were selected, without duplicates.
    public private(set) var ordered: [EntityID] = []
    /// The most recently selected entity still selected, if any.
    public private(set) var primary: EntityID?

    public init() {}

    public var isEmpty: Bool { ordered.isEmpty }

    public func contains(_ id: EntityID) -> Bool { ordered.contains(id) }

    /// Replaces the selection. The last identifier becomes primary.
    public mutating func replace(with ids: [EntityID]) {
        ordered = []
        add(ids)
    }

    /// Adds identifiers not already selected. The last one given becomes
    /// primary, even if it was already selected.
    public mutating func add(_ ids: [EntityID]) {
        for id in ids where !ordered.contains(id) {
            ordered.append(id)
        }
        if let last = ids.last { primary = last }
    }

    /// Removes identifiers. If the primary is removed, the latest remaining
    /// selection becomes primary.
    public mutating func subtract(_ ids: [EntityID]) {
        ordered.removeAll { ids.contains($0) }
        repairPrimary()
    }

    public mutating func clear() {
        ordered = []
        primary = nil
    }

    /// Drops every identifier `keep` rejects.
    public mutating func prune(keeping keep: (EntityID) -> Bool) {
        ordered.removeAll { !keep($0) }
        repairPrimary()
    }

    private mutating func repairPrimary() {
        if let primary, ordered.contains(primary) { return }
        primary = ordered.last
    }
}

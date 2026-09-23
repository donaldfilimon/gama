/// One entry in the incremental change feed a runtime projection consumes.
///
/// Changes name *what* changed; the consumer reads the current value from the
/// document. That keeps the feed small and means a projection that applies the
/// feed in order always converges on the document (spec §10: update only the
/// affected runtime objects, never rebuild the scene).
///
/// Ordering guarantees: a created subtree is reported parent first; a deleted
/// subtree is reported children first.
public enum SceneChange: Hashable, Sendable {
    case entityCreated(EntityID)
    case entityDeleted(EntityID)
    case renamed(EntityID)
    case reparented(EntityID)
    case componentSet(EntityID, ComponentKind)
    case componentRemoved(EntityID, ComponentKind)
    /// A graph was created, deleted, or edited (ADR 0007). Graphs are not
    /// projected, so a renderer may ignore this.
    case graphChanged(GraphID)
}

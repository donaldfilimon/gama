/// Why a command, transaction, or history operation was refused.
///
/// Every refusal leaves the ``EditorSession`` exactly as it was: document,
/// history, revision, selection, and pending changes.
public enum AuthoringError: Error, Hashable, Sendable {
    case missingEntity(EntityID)
    case duplicateEntity(EntityID)
    case wouldCreateCycle(entity: EntityID, parent: EntityID)
    case invalidIndex(Int, count: Int)
    case invalidTransform(String)
    case invalidMaterial(String)
    case invalidLight(String)
    case invalidCamera(String)
    case componentAbsent(EntityID, ComponentKind)
    case emptyTransaction
    case nothingToUndo
    case nothingToRedo
    /// A command produced a document that fails ``SceneDocument/validate()``.
    /// This is a bug in the command, and the result is discarded.
    case invariantViolated(String)
}

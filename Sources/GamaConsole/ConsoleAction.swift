public import GamaAuthoring

/// What one console line asks for (ADR 0006).
///
/// Document edits are the same ``DocumentCommand``s every other surface
/// produces, so a console edit is undone, redone, validated, and projected
/// exactly like a toolbar or inspector edit. The editor-level intents
/// (`add`, `select`, `undo`, `redo`) name the same model operations the
/// toolbar buttons call, so they share their naming, placement, and
/// selection policy instead of re-implementing it.
public enum ConsoleAction: Sendable {
    /// Commands to execute as one undoable step. A single command runs under
    /// its own label, exactly as a panel would run it; several run as one
    /// transaction under `label`.
    case edit(label: String, commands: [any DocumentCommand])
    /// The toolbar's "Add <primitive>".
    case addPrimitive(Primitive)
    /// The toolbar's "Add Light", with the requested kind.
    case addLight(LightKind)
    /// The toolbar's "Add Camera".
    case addCamera
    /// Replaces the selection; an empty list clears it.
    case select([EntityID])
    case undo
    case redo
    /// Text to show; changes nothing.
    case help(String)
}

/// Why a console line was not understood. Nothing is executed for it.
public struct ConsoleError: Error, Hashable, Sendable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

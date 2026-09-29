public import GamaAuthoring

/// Why a USDA file could not be read. Every case names the line it refers to,
/// except ``invalid(_:)``, where the parsed document as a whole fails
/// ``SceneDocument/validate()``.
public enum USDError: Error, Hashable, Sendable {
    /// The text is not well-formed USDA.
    case syntax(line: Int, String)
    /// Well-formed USDA that Gama's subset does not cover (ADR 0005), such as
    /// an unknown prim type or a newer `gama:formatVersion`.
    case unsupported(line: Int, String)
    /// The file parsed, but the document it describes is invalid.
    case invalid(AuthoringError)
}

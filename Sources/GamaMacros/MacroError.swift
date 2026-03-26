// MacroError.swift — Shared error type for GamaMacros

/// Simple error type for macro diagnostics.
enum MacroError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

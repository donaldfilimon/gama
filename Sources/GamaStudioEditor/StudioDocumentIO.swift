//  StudioDocumentIO.swift — GamaStudioEditor
//
//  File access for USDA documents (ADR 0005). GamaUSD stays stdlib-only and
//  works on text; this is the one place Foundation touches the disk.

public import Foundation
public import GamaAuthoring
import GamaUSD

/// Reads and writes Gama Studio documents as `.usda` files.
public enum StudioDocumentIO {
    /// The file extension Save offers and Open accepts.
    public static let fileExtension = "usda"

    /// Reads a document written by ``write(_:to:)`` (or by another USD tool
    /// that reformatted one). Throws the file error or a `USDError`.
    public static func read(from url: URL) throws -> SceneDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try sceneDocument(fromUSDA: text)
    }

    /// Writes `document` as UTF-8 USDA, atomically: a failed write leaves any
    /// existing file untouched.
    public static func write(_ document: SceneDocument, to url: URL) throws {
        try Data(usdaString(from: document).utf8).write(to: url, options: .atomic)
    }

    /// A one-line explanation of a read or write failure for an alert or
    /// stderr, naming the USDA line when there is one.
    public static func describe(_ error: any Error) -> String {
        guard let usd = error as? USDError else { return error.localizedDescription }
        switch usd {
        case .syntax(let line, let message): return "Line \(line): \(message)."
        case .unsupported(let line, let message): return "Line \(line): unsupported: \(message)."
        case .invalid(let reason): return "The file describes an invalid scene: \(reason)."
        }
    }
}

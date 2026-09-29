import Foundation
import Testing

// GamaCore is the pure-Swift layer: it must import neither Qt nor CGamaQt.
// This scans the sources on disk so a stray import fails the gate even when
// it would still compile.

/// Lines in `source` that import `CGamaQt` or mention `Qt`, as "line: text".
func qtLayeringViolations(in source: String) -> [String] {
    source.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .filter { $0.element.contains("import CGamaQt") || $0.element.contains("Qt") }
        .map { "\($0.offset + 1): \($0.element)" }
}

private func gamaCoreSourceFiles() throws -> [URL] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GamaTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root
        .appendingPathComponent("Sources/GamaCore", isDirectory: true)
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
        return []
    }
    return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}

@Test func gamaCoreImportsNeitherQtNorCGamaQt() throws {
    let files = try gamaCoreSourceFiles()
    // An empty list means the path is wrong; without this the test passes vacuously.
    #expect(!files.isEmpty)
    for file in files {
        let hits = qtLayeringViolations(in: try String(contentsOf: file, encoding: .utf8))
        #expect(hits.isEmpty, "\(file.lastPathComponent) breaks the GamaCore layering: \(hits)")
    }
}

@Test func layeringDetectorFlagsQtImports() {
    #expect(qtLayeringViolations(in: "import Foundation\nimport CGamaQt\n") == ["2: import CGamaQt"])
    #expect(qtLayeringViolations(in: "import QtCore") == ["1: import QtCore"])
    #expect(qtLayeringViolations(in: "import Foundation\nstruct Resolver {}\n").isEmpty)
}

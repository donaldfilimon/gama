//  IPadToolbarWrapTests.swift — GamaStudioEditorTests
//
//  ADR 0020: on iPad portrait the regular (single-row) toolbar was one row
//  wider than the screen, so buttons after "Duplicate" (Delete, Undo, Redo,
//  Frame, Graph) were unreachable. This pins that every toolbar label is
//  fully painted, not clipped, at the measured iPad-portrait column count
//  and at a wide column count, with and without the touch-host file
//  buttons (`DocumentActions`).
//
//  The 92-column figure is the iPad Pro 11-inch (M5) portrait width
//  (834 pt) divided by the measured `GamaHostView` monospaced cell width:
//  `NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)`, glyph "M",
//  `ceil` — the same measurement GamaHostView performs — comes to 9.0 pt on
//  this machine, and 834 / 9.0 = 92.67, floored to 92. That is above
//  `StudioRootView.compactWidth` (86), so the regular layout is the one in
//  play, matching the measured bug (the cut trailing "Duplicat…" lines up
//  with a toolbar row about 92-93 columns wide).

#if canImport(RealityKit)

import GamaAuthoring
import GamaCore
import GamaDraw
import GamaStudioEditor
import Testing

@MainActor
@Suite("iPad portrait toolbar wrap")
struct IPadToolbarWrapTests {
    /// Derived iPad Pro 11-inch (M5) portrait width in columns; see the
    /// file header for the measurement.
    static let iPadPortraitWidth = 92
    /// A width comfortably wider than the full single-row toolbar, so the
    /// wrap must collapse back to one row here.
    static let wideWidth = 200

    /// Every regular-layout toolbar label, full (non-abbreviated) form, in
    /// the order `StudioRootView` builds them. Button labels are painted
    /// as `" <title> "` (`Button.init(_:action:)` pads with one space each
    /// side), so searching for the padded form also proves the label was
    /// not truncated mid-word.
    static let creationLabels = ["Add Box", "Add Sphere", "Add Cone", "Add Light", "Add Camera"]
    static let editingLabels = ["Duplicate", "Delete", "Undo", "Redo", "Frame"]
    static let fileLabels = ["Open", "Save", "Save As"]

    func painted(_ frame: LaidOutNode, size: Size) -> String {
        paintedRows(frame, size: size).joined(separator: "\n")
    }

    func paintedRows(_ frame: LaidOutNode, size: Size) -> [String] {
        var buffer = CellBuffer(size: size)
        buffer.clearBack()
        CellPainter.paint(frame, into: &buffer)
        return (0..<size.height).map { buffer.rowText($0) }
    }

    /// Whether `label`, exactly as a `Button` paints it (leading pad space,
    /// then the title), appears in `text` as a whole word: the character
    /// right after it, if any, is a space or a newline, never another
    /// letter — which is what a mid-word clip would otherwise leave behind
    /// (e.g. "Grap" from a clipped "Graph" would not match at all, and a
    /// clip that happened to land on a word boundary still cannot produce
    /// this exact followed-by-boundary shape by accident). The trailing pad
    /// space is not required: `CellBuffer.rowText` trims trailing blanks,
    /// so a label painted last on its row loses that space along with the
    /// row's unused columns even when it is not clipped.
    func labelIsFullyVisible(_ text: String, _ label: String) -> Bool {
        let needle = Array(" " + label)
        let chars = Array(text)
        guard !needle.isEmpty, needle.count <= chars.count else { return false }
        var start = 0
        while start + needle.count <= chars.count {
            if Array(chars[start..<(start + needle.count)]) == needle {
                let after = start + needle.count
                if after == chars.count { return true }
                if chars[after] == " " || chars[after] == "\n" { return true }
            }
            start += 1
        }
        return false
    }

    func expectLabelsFullyVisible(
        _ text: String, _ labels: [String], sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for label in labels {
            #expect(labelIsFullyVisible(text, label), "\(label) is clipped or missing", sourceLocation: sourceLocation)
        }
    }

    /// Whether `firstLabel` and `lastLabel` are painted on the same line of
    /// `text` — true for a single-row toolbar, false once it has wrapped
    /// into more than one row. Black-box on purpose: `StudioRootView` and
    /// its wrap threshold are not `public`, so a test can only observe the
    /// painted result, never the private label copies or math behind it.
    func toolbarSpansOneRow(_ text: String, firstLabel: String, lastLabel: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        func lineIndex(containing needle: String) -> Int? {
            lines.firstIndex { $0.contains(needle) }
        }
        guard let first = lineIndex(containing: firstLabel), let last = lineIndex(containing: lastLabel) else {
            return false
        }
        return first == last
    }

    @Test func everyToolbarLabelFitsAtIPadPortraitWidthWithFileButtons() throws {
        let size = Size(width: Self.iPadPortraitWidth, height: 44)
        let model = StudioModel(document: StudioModel.sampleScene())
        let documents = DocumentActions(open: {}, save: {}, saveAs: {})
        var host = try FrameHost(app: StudioApp(model: model, documents: documents))
        let text = painted(host.pump(size: size), size: size)

        expectLabelsFullyVisible(text, Self.fileLabels)
        expectLabelsFullyVisible(text, Self.creationLabels)
        expectLabelsFullyVisible(text, Self.editingLabels)
        #expect(labelIsFullyVisible(text, "Graph"), "Graph toggle is clipped or missing")

        // Every toolbar action must still be reachable by identity.
        for id in StudioApp.fileActionIDs + StudioApp.toolbarActionIDs {
            host.perform(id)
        }
    }

    @Test func everyToolbarLabelFitsAtIPadPortraitWidthWithoutFileButtons() throws {
        let size = Size(width: Self.iPadPortraitWidth, height: 44)
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        let text = painted(host.pump(size: size), size: size)

        expectLabelsFullyVisible(text, Self.creationLabels)
        expectLabelsFullyVisible(text, Self.editingLabels)
        #expect(labelIsFullyVisible(text, "Graph"), "Graph toggle is clipped or missing")
        #expect(!text.contains(" Open "), "no documents host means no file buttons")
    }

    @Test func everyToolbarLabelFitsAtAWideWidth() throws {
        let size = Size(width: Self.wideWidth, height: 40)
        let model = StudioModel(document: StudioModel.sampleScene())
        let documents = DocumentActions(open: {}, save: {}, saveAs: {})
        var host = try FrameHost(app: StudioApp(model: model, documents: documents))
        let text = painted(host.pump(size: size), size: size)

        expectLabelsFullyVisible(text, Self.fileLabels)
        expectLabelsFullyVisible(text, Self.creationLabels)
        expectLabelsFullyVisible(text, Self.editingLabels)
        #expect(labelIsFullyVisible(text, "Graph"), "Graph toggle is clipped or missing")
    }

    /// `regularToolbarFits(width:)` (private to `StudioRootView`) decides
    /// the wrap threshold from hand-maintained copies of the button
    /// labels, not from the live render — so nothing stops those copies
    /// drifting from the real `Button` titles in `fileButtons`,
    /// `creationButtons(short:)`, and `editingButtons(short:)`. This test
    /// cannot see that private threshold, so it proves the two agree the
    /// only way a black box can: it measures the toolbar's actual painted
    /// content width at a wide surface (where it is known to still fit on
    /// one row), derives the boundary that width implies, and checks it —
    /// still one row right at that boundary, wrapped (but every label
    /// still fully visible) one column narrower. If a label copy drifts
    /// from the real title, the computed threshold moves away from the
    /// actual rendered width and one of those two boundary checks fails.
    ///
    /// The boundary is the measured content width plus one, not the
    /// measured width itself: `CellBuffer.rowText` trims trailing blanks,
    /// so the last button's own trailing pad space (`Button` pads
    /// `" <title> "` on both sides) is invisible in the measured text even
    /// though the layout still needs that one extra column to paint it
    /// without wrapping.
    @Test func toolbarWrapThresholdMatchesTheActuallyRenderedWidth() throws {
        for hasDocuments in [true, false] {
            let wideSize = Size(width: 260, height: 44)
            let wideModel = StudioModel(document: StudioModel.sampleScene())
            let wideDocuments = hasDocuments ? DocumentActions(open: {}, save: {}, saveAs: {}) : nil
            var wideHost = try FrameHost(app: StudioApp(model: wideModel, documents: wideDocuments))
            let wideRows = paintedRows(wideHost.pump(size: wideSize), size: wideSize)
            let firstLabel = hasDocuments ? "Open" : "Add Box"
            #expect(
                toolbarSpansOneRow(wideRows.joined(separator: "\n"), firstLabel: firstLabel, lastLabel: "Graph"),
                "260 columns should already be one row (documents: \(hasDocuments))"
            )
            // The toolbar's actual painted content width, trailing blanks
            // (including the last button's own trailing pad space) already
            // trimmed by `rowText`; +1 restores that pad space to get the
            // true column count the layout needs to avoid wrapping.
            let requiredWidth = wideRows[0].count + 1

            let exactSize = Size(width: requiredWidth, height: 44)
            let exactModel = StudioModel(document: StudioModel.sampleScene())
            let exactDocuments = hasDocuments ? DocumentActions(open: {}, save: {}, saveAs: {}) : nil
            var exactHost = try FrameHost(app: StudioApp(model: exactModel, documents: exactDocuments))
            let exactText = painted(exactHost.pump(size: exactSize), size: exactSize)
            expectLabelsFullyVisible(exactText, hasDocuments ? Self.fileLabels : [])
            expectLabelsFullyVisible(exactText, Self.creationLabels)
            expectLabelsFullyVisible(exactText, Self.editingLabels)
            #expect(
                toolbarSpansOneRow(exactText, firstLabel: firstLabel, lastLabel: "Graph"),
                "at exactly the required width (\(requiredWidth), documents: \(hasDocuments)) the toolbar should still be one row"
            )

            let narrowSize = Size(width: requiredWidth - 1, height: 44)
            let narrowModel = StudioModel(document: StudioModel.sampleScene())
            let narrowDocuments = hasDocuments ? DocumentActions(open: {}, save: {}, saveAs: {}) : nil
            var narrowHost = try FrameHost(app: StudioApp(model: narrowModel, documents: narrowDocuments))
            let narrowText = painted(narrowHost.pump(size: narrowSize), size: narrowSize)
            expectLabelsFullyVisible(narrowText, hasDocuments ? Self.fileLabels : [])
            expectLabelsFullyVisible(narrowText, Self.creationLabels)
            expectLabelsFullyVisible(narrowText, Self.editingLabels)
            #expect(
                !toolbarSpansOneRow(narrowText, firstLabel: firstLabel, lastLabel: "Graph"),
                "one column narrower than the required width (\(requiredWidth - 1), documents: \(hasDocuments)) must wrap"
            )
        }
    }
}
#endif

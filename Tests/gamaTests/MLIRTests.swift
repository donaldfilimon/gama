//  MLIRTests.swift — MLIR lowering.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

@Suite("MLIR")
struct MLIRTests {
    @Test("structural lowering well formed")
    func structuralLoweringWellFormed() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 1,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("hello \"mlir\"", style: TextStyle(foreground: .red)),
                .spacer(minLength: 2),
                .divider(style: .plain),
            ]
        )
        let mlir = GamaLowering.lower(module: node, name: "t")
        #expect(mlir.contains("\"gama.module\"()"))
        #expect(mlir.contains("sym_name = \"t\""))
        #expect(mlir.contains("\"gama.stack\"()"))
        #expect(mlir.contains("axis = \"v\""))
        #expect(mlir.contains(#"text = "hello \"mlir\"""#))
        #expect(mlir.contains("dense<[224, 64, 64]> : tensor<3xi8>"))
        #expect(mlir.contains("min = 2 : i64"))
        #expect(mlir.contains("\"gama.divider\"()"))
        #expect(mlir.filter { $0 == "{" }.count == mlir.filter { $0 == "}" }.count)
    }

    @Test("group sentinel lowers to gama.group")
    func groupSentinelLowersToGamaGroup() {
        let node = RenderNode.group(children: [
            .text("a", style: .plain), .text("b", style: .plain),
        ])
        let mlir = GamaLowering.lower(module: node, name: "grouped")
        // Proves the Capabilities.md claim: the flatten sentinel reaches
        // the dialect as its own op, not as an overlay.
        #expect(mlir.contains("\"gama.group\"()"))
        #expect(!mlir.contains("\"gama.overlay\"()"))
    }

    @Test("interactive NodeID emits full 64-bit id")
    func interactiveNodeIDEmitsFull64BitId() {
        let id = NodeID(raw: 1 << 40)
        let node = RenderNode.interactive(
            id: id, focusable: true, child: .text("x", style: .plain))
        let mlir = GamaLowering.lower(module: node, name: "id64")
        #expect(mlir.contains("id = \(Int64(bitPattern: id.raw)) : i64"))
        #expect(!mlir.contains("id = 0 : i64"))
    }

    @Test("frame-annotated lowering carries geometry")
    func frameAnnotatedLoweringCarriesGeometry() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [.text("hi", style: .plain)]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 8, height: 2))
        let mlir = GamaLowering.lower(laidOut: laid, name: "geo")
        #expect(mlir.contains("x = 0 : i64"))
        #expect(mlir.contains("w = "))
        #expect(mlir.contains("\"gama.text\"()"))
    }
}

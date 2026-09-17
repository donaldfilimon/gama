//  ActionTests.swift — action registration and dispatch.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

@Suite("Actions")
struct ActionTests {
    @Test("collect interactive order")
    func collectInteractiveOrder() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .interactive(id: NodeID.root.child(1), focusable: true, child: .text("a", style: .plain)),
                .interactive(id: NodeID.root.child(2), focusable: true, child: .text("b", style: .plain)),
            ]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 4))
        var out: [InteractiveRegion] = []
        laid.collectInteractive(into: &out)
        #expect(out.map(\.id) == [NodeID.root.child(1), NodeID.root.child(2)])
    }

    @Test("disabled button does not register and is not focusable")
    func disabledButtonDoesNotRegisterAndIsNotFocusable() {
        let pressed = TestBox(false)
        let button = Button("go") { pressed.value = true }.disabled()
        let registered = TestBox<(() -> Void)?>(nil)
        let ctx = BuildContext(id: .root, registerAction: { _, action in registered.value = action })
        let node = button.render(in: ctx)

        guard case .interactive(_, let focusable, _) = node else {
            Issue.record("expected interactive node, got \(node)")
            return
        }
        #expect(!focusable)
        #expect(registered.value == nil)
        #expect(!pressed.value)
    }

    @Test("enabled button still registers")
    func enabledButtonStillRegisters() {
        let pressed = TestBox(false)
        let button = Button("go") { pressed.value = true }.disabled(false)
        let registered = TestBox<(() -> Void)?>(nil)
        let context = BuildContext(id: .root, registerAction: { _, action in registered.value = action })
        let node = button.render(in: context)
        guard case .interactive(_, let focusable, _) = node else {
            Issue.record("expected interactive node")
            return
        }
        #expect(focusable)
        registered.value?()
        #expect(pressed.value)
    }
}

//  NativePresentationTests.swift — the portable presentation tree and its
//  diff (ADR 0017, native-presentation plan Task 6).

import Testing

@testable import GamaCore

private let bounds = Rect(x: 0, y: 0, width: 40, height: 10)

private func present(
    _ node: RenderNode, controls: [NodeID: ControlDescriptor] = [:], regions: [NativeRegionFrame] = []
) -> [PresentedNode] {
    PresentedNode.tree(
        from: LayoutEngine.layout(node, in: bounds), controls: controls, regions: regions)
}

private func path(_ indices: Int...) -> PresentationID {
    var id = NodeID.root
    for index in indices { id = id.child(index) }
    return .path(id.raw)
}

private let buttonID = NodeID.root.child(100)
private let fieldID = NodeID.root.child(101)

@Suite("Presentation tree")
struct PresentationTreeTests {
    @Test("only text, divider, background, border and interactive produce views")
    func whichNodesProduceViews() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 0, alignment: .topLeading,
            children: [
                .padding(EdgeInsets(all: 1), child: .text("a", style: .plain)),
                .spacer(minLength: 0),
                .group(children: [.empty]),
                .divider(style: .plain),
                .styled(TextStyle(attributes: [.bold]), child: .frame(width: 3, height: 1, alignment: .center, child: .text("b", style: .plain))),
            ])
        let tree = present(node)
        #expect(tree.map(\.id) == [path(0, 0), path(3), path(4, 0, 0)])
        #expect(tree[0].kind == .label("a"))
        #expect(tree[1].kind == .separator(.horizontal))
        #expect(tree[2].kind == .label("b"))
        #expect(tree.allSatisfy { $0.children.isEmpty })
    }

    @Test("frames are relative to the nearest presented ancestor")
    func relativeFrames() {
        let node = RenderNode.padding(
            EdgeInsets(top: 2, leading: 3, bottom: 0, trailing: 0),
            child: .border(
                .single, style: .plain, title: "T",
                child: .padding(EdgeInsets(all: 1), child: .text("x", style: .plain))))
        let tree = present(node)
        #expect(tree.count == 1)
        #expect(tree[0].frame.origin == Point(x: 3, y: 2))
        #expect(tree[0].kind == .container(background: .default, border: .single, title: "T"))
        // Border inset 1 plus padding 1, relative to the border.
        #expect(tree[0].children.first?.frame.origin == Point(x: 2, y: 2))
    }

    @Test("identity is stable across identical rebuilds")
    func stableIdentity() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 1, alignment: .center,
            children: [
                .interactive(id: buttonID, focusable: true, child: .text("ok", style: .plain)),
                .background(.blue, child: .text("z", style: .plain)),
            ])
        let first = present(node)
        let second = present(node)
        #expect(first == second)
        #expect(first[0].id == .node(buttonID))
        #expect(first[1].id == path(1))
        #expect(first[1].children.first?.id == path(1, 0))
    }

    @Test("labels carry the resolved inherited style, outer wrappers winning")
    func resolvedStyle() {
        let outer = TextStyle(foreground: .red, attributes: [.bold])
        let node = RenderNode.styled(outer, child: .text("s", style: TextStyle(foreground: .green, attributes: [.italic])))
        let tree = present(node)
        #expect(tree[0].style == TextStyle(foreground: .red, attributes: [.bold, .italic]))
    }

    @Test("descriptors and regions attach to their interactive nodes")
    func descriptorsAndRegions() {
        let regionID = NativeRegionID("map")
        let regionNode = NodeID.root.child(102)
        let node = RenderNode.stack(
            axis: .vertical, spacing: 0, alignment: .topLeading,
            children: [
                .interactive(id: buttonID, focusable: true, child: .text(" Go ", style: .plain)),
                .interactive(id: fieldID, focusable: true, child: .text("t", style: .plain)),
                .interactive(id: regionNode, focusable: true, child: .text("fallback", style: .plain)),
                .interactive(id: NodeID.root.child(103), focusable: false, child: .text("g", style: .plain)),
            ])
        let tree = present(
            node,
            controls: [
                buttonID: .button(title: "Go", isEnabled: true),
                fieldID: .textField(placeholder: "p", text: "t", isEnabled: true, setText: { _ in }),
            ],
            regions: [NativeRegionFrame(id: regionID, node: regionNode, frame: .zero, isFocused: false)])
        #expect(tree[0].kind == .control(.button(title: "Go", isEnabled: true)))
        #expect(tree[0].children.isEmpty)
        #expect(tree[1].kind == .control(.textField(placeholder: "p", text: "t", isEnabled: true, setText: { _ in })))
        #expect(tree[2].kind == .nativeRegion(regionID))
        #expect(tree[2].children.first?.kind == .label("fallback"))
        #expect(tree[3].kind == .focusGroup(focusable: false))
        #expect(tree[3].children.first?.kind == .label("g"))
    }

    @Test("duplicate interactive identities present once, as the last occurrence")
    func duplicateInteractiveIdentities() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 0, alignment: .topLeading,
            children: [
                .interactive(id: buttonID, focusable: true, child: .text("first", style: .plain)),
                .interactive(id: buttonID, focusable: true, child: .text("second", style: .plain)),
            ])
        let tree = present(node)
        #expect(tree.map(\.id) == [.node(buttonID)])
        #expect(tree.first?.frame.origin == Point(x: 0, y: 1))
        #expect(tree.first?.children.map(\.kind) == [.label("second")])
    }

    @Test("a button with a composite label presents its label inside")
    func compositeButtonPresentsChildren() {
        let node = RenderNode.interactive(
            id: buttonID, focusable: true,
            child: .stack(
                axis: .horizontal, spacing: 0, alignment: .center,
                children: [.text("A", style: .plain), .text("B", style: .plain)]))
        let tree = present(node, controls: [buttonID: .button(title: nil, isEnabled: true)])
        #expect(tree[0].children.map(\.kind) == [.label("A"), .label("B")])
    }
}

private func label(_ id: PresentationID, _ text: String, x: Int = 0, children: [PresentedNode] = []) -> PresentedNode {
    PresentedNode(id: id, kind: .label(text), frame: Rect(x: x, y: 0, width: 1, height: 1), style: .plain, children: children)
}

private func box(_ id: PresentationID, children: [PresentedNode]) -> PresentedNode {
    PresentedNode(
        id: id, kind: .container(background: .blue, border: nil, title: nil),
        frame: Rect(x: 0, y: 0, width: 10, height: 10), style: .plain, children: children)
}

@Suite("Presentation diff")
struct PresentationDiffTests {
    private let a = PresentationID.path(1)
    private let b = PresentationID.path(2)
    private let c = PresentationID.node(NodeID(raw: 3))
    private let root = PresentationID.path(9)

    @Test("identical trees produce no operations")
    func identical() {
        let tree = [box(root, children: [label(a, "a"), label(b, "b")])]
        #expect(PresentationDiff.between(tree, tree).isEmpty)
    }

    @Test("an empty old tree inserts everything in pre-order")
    func insertAll() {
        let tree = [box(root, children: [label(a, "a")])]
        #expect(
            PresentationDiff.between([], tree) == [
                .insert(
                    id: root, kind: .container(background: .blue, border: nil, title: nil), style: .plain,
                    parent: nil, index: 0, frame: Rect(x: 0, y: 0, width: 10, height: 10)),
                .insert(id: a, kind: .label("a"), style: .plain, parent: root, index: 0, frame: Rect(x: 0, y: 0, width: 1, height: 1)),
            ])
    }

    @Test("a text change is an update")
    func textUpdate() {
        let old = [label(a, "a")]
        let new = [label(a, "A")]
        #expect(PresentationDiff.between(old, new) == [.update(id: a, kind: .label("A"), style: .plain)])
    }

    @Test("a style change is an update")
    func styleUpdate() {
        var changed = label(a, "a")
        changed.style = TextStyle(attributes: [.bold])
        #expect(
            PresentationDiff.between([label(a, "a")], [changed]) == [
                .update(id: a, kind: .label("a"), style: TextStyle(attributes: [.bold]))
            ])
    }

    @Test("a descriptor change is an update, ignoring closures")
    func descriptorUpdate() {
        func field(_ text: String) -> PresentedNode {
            PresentedNode(
                id: c, kind: .control(.textField(placeholder: "", text: text, isEnabled: true, setText: { _ in })),
                frame: .zero, style: .plain)
        }
        #expect(PresentationDiff.between([field("x")], [field("x")]).isEmpty)
        let ops = PresentationDiff.between([field("x")], [field("y")])
        #expect(ops.count == 1)
        guard case .update(let id, .control(.textField(_, let text, _, _)), _)? = ops.first else {
            Issue.record("expected an update"); return
        }
        #expect(id == c)
        #expect(text == "y")
    }

    @Test("a frame change is a setFrame")
    func frameChange() {
        #expect(
            PresentationDiff.between([label(a, "a")], [label(a, "a", x: 4)]) == [
                .setFrame(id: a, frame: Rect(x: 4, y: 0, width: 1, height: 1))
            ])
    }

    @Test("a reorder moves both siblings")
    func reorder() {
        let old = [box(root, children: [label(a, "a"), label(b, "b")])]
        let new = [box(root, children: [label(b, "b"), label(a, "a")])]
        #expect(
            PresentationDiff.between(old, new) == [
                .move(id: b, parent: root, index: 0),
                .move(id: a, parent: root, index: 1),
            ])
    }

    @Test("re-parenting is a move")
    func reparent() {
        let old = [box(root, children: [label(a, "a")])]
        let new = [box(root, children: []), label(a, "a")]
        #expect(PresentationDiff.between(old, new) == [.move(id: a, parent: nil, index: 1)])
    }

    @Test("a kind change is a remove then an insert")
    func kindChange() {
        let old = [label(a, "a")]
        let new = [PresentedNode(id: a, kind: .separator(.vertical), frame: Rect(x: 0, y: 0, width: 1, height: 1), style: .plain)]
        #expect(
            PresentationDiff.between(old, new) == [
                .remove(id: a),
                .insert(id: a, kind: .separator(.vertical), style: .plain, parent: nil, index: 0, frame: Rect(x: 0, y: 0, width: 1, height: 1)),
            ])
    }

    @Test("a control kind change replaces the view")
    func controlKindChange() {
        let old = [PresentedNode(id: c, kind: .control(.button(title: "x", isEnabled: true)), frame: .zero, style: .plain)]
        let new = [PresentedNode(id: c, kind: .control(.toggle(title: "x", isOn: false, isEnabled: true)), frame: .zero, style: .plain)]
        #expect(
            PresentationDiff.between(old, new) == [
                .remove(id: c),
                .insert(id: c, kind: .control(.toggle(title: "x", isOn: false, isEnabled: true)), style: .plain, parent: nil, index: 0, frame: .zero),
            ])
    }

    @Test("a button switching between a composite and a titled label replaces the view")
    func buttonLabelShapeChange() {
        let composite = PresentedNode(
            id: c, kind: .control(.button(title: nil, isEnabled: true)), frame: .zero, style: .plain,
            children: [label(a, "a")])
        let titled = PresentedNode(id: c, kind: .control(.button(title: "X", isEnabled: true)), frame: .zero, style: .plain)
        #expect(
            PresentationDiff.between([composite], [titled]) == [
                .remove(id: c),
                .remove(id: a),
                .insert(id: c, kind: .control(.button(title: "X", isEnabled: true)), style: .plain, parent: nil, index: 0, frame: .zero),
            ])
        #expect(
            PresentationDiff.between([titled], [composite]) == [
                .remove(id: c),
                .insert(id: c, kind: .control(.button(title: nil, isEnabled: true)), style: .plain, parent: nil, index: 0, frame: .zero),
                .insert(id: a, kind: .label("a"), style: .plain, parent: c, index: 0, frame: Rect(x: 0, y: 0, width: 1, height: 1)),
            ])
    }

    @Test("duplicate identities present only the last occurrence and its children")
    func duplicateIdentities() {
        let first = PresentedNode(
            id: c, kind: .focusGroup(focusable: true), frame: .zero, style: .plain, children: [label(a, "a")])
        let second = PresentedNode(
            id: c, kind: .focusGroup(focusable: true), frame: Rect(x: 5, y: 0, width: 1, height: 1), style: .plain,
            children: [label(b, "b")])
        let ops = PresentationDiff.between([], [first, second])
        #expect(
            ops == [
                .insert(
                    id: c, kind: .focusGroup(focusable: true), style: .plain, parent: nil, index: 0,
                    frame: Rect(x: 5, y: 0, width: 1, height: 1)),
                .insert(id: b, kind: .label("b"), style: .plain, parent: c, index: 0, frame: Rect(x: 0, y: 0, width: 1, height: 1)),
            ])
        #expect(PresentationDiff.between([first, second], [first, second]).isEmpty)
    }

    @Test("removed views are removed in old pre-order before any insert")
    func removals() {
        let old = [box(root, children: [label(a, "a"), label(b, "b")])]
        let new = [label(c, "c")]
        #expect(
            PresentationDiff.between(old, new) == [
                .remove(id: root),
                .remove(id: a),
                .remove(id: b),
                .insert(id: c, kind: .label("c"), style: .plain, parent: nil, index: 0, frame: Rect(x: 0, y: 0, width: 1, height: 1)),
            ])
    }
}

private struct PresentedFormApp: App {
    let text = Signal("hi")
    init() {}
    var scenes: some Scene {
        Window("Form", id: "main", role: .primary) {
            VStack {
                Button("Save", action: {})
                TextField("Name", text: text.binding())
                ProgressView(value: 0.5, label: "Load")
            }
        }
    }
}

@Suite("Presentation from a host")
struct PresentationHostTests {
    @Test("a pumped frame with its control table presents platform controls")
    func hostFramePresentsControls() throws {
        var host = try FrameHost(app: PresentedFormApp())
        let laid = host.pump(size: Size(width: 40, height: 6))
        let tree = PresentedNode.tree(from: laid, controls: host.controls, regions: host.nativeRegions)
        let kinds = tree.map(\.kind)
        #expect(
            kinds == [
                .control(.button(title: "Save", isEnabled: true)),
                .control(.textField(placeholder: "Name", text: "hi", isEnabled: true, setText: { _ in })),
                .control(.progress(fraction: 0.5, label: "Load")),
            ])
        #expect(tree.allSatisfy { $0.children.isEmpty })
        #expect(PresentationDiff.between(tree, tree).isEmpty)
    }

    @Test("a focused composite button presents its label without the cell focus highlight")
    func compositeButtonDropsCellFocusStyle() throws {
        var host = try FrameHost(app: CompositeButtonApp())
        _ = host.pump(size: Size(width: 40, height: 4))
        let laid = host.pump(size: Size(width: 40, height: 4))
        let tree = PresentedNode.tree(from: laid, controls: host.controls, regions: host.nativeRegions)
        guard let button = tree.first, button.kind == .control(.button(title: nil, isEnabled: true)) else {
            Issue.record("no composite button"); return
        }
        let focused = host.focusedID
        #expect(focused.map(PresentationID.node) == button.id)
        #expect(button.children.map(\.kind) == [.label("A"), .label("B")])
        #expect(button.children.allSatisfy { $0.style.background.isDefault && $0.style.foreground.isDefault })
    }
}

private struct CompositeButtonApp: App {
    init() {}
    var scenes: some Scene {
        Window("Composite", id: "main", role: .primary) {
            Button(action: {}) {
                HStack {
                    Text("A")
                    Text("B")
                }
            }
        }
    }
}

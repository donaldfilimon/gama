//  GraphPanel.swift — GamaStudioEditor
//
//  The graph editor (ADR 0007): one reusable panel for every graph domain,
//  shown in place of the inspector while the toolbar's "Graph" toggle is on.
//  Like every panel it only reads a Sendable snapshot and forwards button
//  presses to StudioModel, whose graph methods run each edit together with
//  the graph's re-evaluation as one undoable step.

#if canImport(AppKit)

public import GamaCore
import GamaAuthoring
import GamaConsole
import GamaGraph

/// What the graph panel shows, copied from the model on the main actor.
struct GraphPanelState: Sendable {
    struct NodeRow: Sendable {
        var id: GraphNodeID
        var title: String
        var isSelected: Bool
    }

    /// One input of the selected node.
    struct InputRow: Sendable {
        var name: String
        var type: PortType
        /// `n2.color` when connected.
        var link: String?
        /// The constant, formatted, when not connected.
        var value: String?
        var isFloat: Bool
        var isEntity: Bool
        /// Whether the pending output can connect here.
        var acceptsPending: Bool
    }

    struct Selected: Sendable {
        var id: GraphNodeID
        var definition: String
        var inputs: [InputRow]
        var outputs: [GraphPort]
    }

    /// `2/3 material`, beside the previous and next buttons.
    var header: String
    /// The graph's name, on its own line so a long name fits.
    var title: String
    var nodes: [NodeRow]
    var selected: Selected?
    var picker: String?
    var pending: String?
    var hasGraph: Bool

    @MainActor
    init(_ model: StudioModel) {
        guard let graph = model.currentGraph else {
            header = "0/0"
            title = "No graphs"
            nodes = []
            selected = nil
            picker = nil
            pending = nil
            hasGraph = false
            return
        }
        hasGraph = true
        let count = model.session.document.graphOrder.count
        let position = (model.session.document.graphOrder.firstIndex(of: graph.id) ?? 0) + 1
        header = "\(position)/\(count) \(graph.domain.rawValue)"
        title = graph.name
        let registry = model.graphEvaluator.registry
        nodes = graph.order.compactMap { id in
            guard let node = graph.node(id) else { return nil }
            let title = registry.definition(node.definition)?.title ?? node.definition
            return NodeRow(id: id, title: title, isSelected: id == model.selectedGraphNode)
        }
        picker = model.pickedNode?.title
        let pendingType = model.pendingLink.flatMap { graph.node($0.node)?.output($0.port)?.type }
        pending = model.pendingLink.map { "\($0)" }
        if let id = model.selectedGraphNode, let node = graph.node(id) {
            selected = Selected(
                id: id,
                definition: node.definition,
                inputs: node.inputs.map { port in
                    let reference = PortReference(id, port.name)
                    return InputRow(
                        name: port.name,
                        type: port.type,
                        link: graph.connection(into: reference).map { "\($0.from)" },
                        value: node.values[port.name].map { value in
                            if case .entity(let target?) = value {
                                return model.session.document.entity(target)?.name ?? "\(target) (deleted)"
                            }
                            return ConsoleParser.format(value)
                        },
                        isFloat: port.type == .float,
                        isEntity: port.type == .entity,
                        acceptsPending: pendingType.map { $0.canConnect(to: port.type) } ?? false
                    )
                },
                outputs: node.outputs
            )
        } else {
            selected = nil
        }
    }
}

/// The graph editor panel.
struct GraphPanel: View {
    let model: StudioModel
    let state: GraphPanelState

    var body: some View {
        VStack {
            HStack(spacing: 1) {
                Button("<", action: onMain(model) { $0.cycleGraph(by: -1) })
                    .actionIdentity(ActionID("studio.graph.previous"))
                Text(state.header)
                Button(">", action: onMain(model) { $0.cycleGraph(by: 1) })
                    .actionIdentity(ActionID("studio.graph.next"))
            }
            Text(state.title).bold()
            HStack(spacing: 1) {
                Button("New Mat", action: onMain(model) { $0.createGraph(name: "Material Graph", domain: .material) })
                    .actionIdentity(ActionID("studio.graph.newMaterial"))
                Button("New Scene", action: onMain(model) { $0.createGraph(name: "Scene Graph", domain: .scene) })
                    .actionIdentity(ActionID("studio.graph.newScene"))
            }
            if state.hasGraph {
                ForEach(state.nodes) { row in
                    Button(action: onMain(model) { [id = row.id] in $0.selectGraphNode(id) }) {
                        Text(
                            (row.isSelected ? "▸ " : "  ") + "\(row.id) \(row.title)",
                            style: row.isSelected ? TextStyle(attributes: [.inverse]) : .plain
                        )
                    }
                    .actionIdentity(ActionID("studio.graph.node.\(row.id.rawValue)"))
                }
                if let picker = state.picker {
                    HStack(spacing: 1) {
                        Button("<", action: onMain(model) { $0.cycleNodePicker(by: -1) })
                            .actionIdentity(ActionID("studio.graph.picker.previous"))
                        Button("Add \(picker)", action: onMain(model) { model in
                            if let id = model.pickedNode?.id { model.addGraphNode(id) }
                        })
                        .actionIdentity(ActionID("studio.graph.add"))
                        Button(">", action: onMain(model) { $0.cycleNodePicker(by: 1) })
                            .actionIdentity(ActionID("studio.graph.picker.next"))
                    }
                }
                if let pending = state.pending {
                    HStack(spacing: 1) {
                        Text("Link \(pending) →")
                        Button("Cancel", action: onMain(model) { $0.cancelLink() })
                            .actionIdentity(ActionID("studio.graph.cancelLink"))
                    }
                }
                if let selected = state.selected {
                    selectedSection(selected)
                }
                HStack(spacing: 1) {
                    Button("Apply", action: onMain(model) { $0.applyCurrentGraph() })
                        .actionIdentity(ActionID("studio.graph.apply"))
                    Button("Delete Graph", action: onMain(model) { $0.deleteCurrentGraph() })
                        .actionIdentity(ActionID("studio.graph.delete"))
                }
            }
        }
        .frame(maxWidth: .max, maxHeight: .max, alignment: .topLeading)
        .border(title: "Graph")
        .frame(width: 30)
    }

    private func selectedSection(_ selected: GraphPanelState.Selected) -> some View {
        VStack {
            Text("\(selected.id) \(selected.definition)").bold()
            ForEach(selected.inputs) { input in
                inputRow(input, node: selected.id)
            }
            ForEach(selected.outputs) { port in
                HStack(spacing: 1) {
                    Text("→ \(port.name)")
                    Button("Link", action: onMain(model) { [reference = PortReference(selected.id, port.name)] in
                        $0.beginLink(from: reference)
                    })
                    .actionIdentity(ActionID("studio.graph.link.\(port.name)"))
                }
            }
            Button("Remove Node", action: onMain(model) { $0.removeSelectedGraphNode() })
                .actionIdentity(ActionID("studio.graph.remove"))
        }
    }

    private func inputRow(_ input: GraphPanelState.InputRow, node: GraphNodeID) -> some View {
        let reference = PortReference(node, input.name)
        return HStack(spacing: 1) {
            if let link = input.link {
                Text("\(input.name) ← \(link)")
                Button("x", action: onMain(model) { $0.disconnect(reference) })
                    .actionIdentity(ActionID("studio.graph.disconnect.\(input.name)"))
            } else {
                Text("\(input.name) = \(input.value ?? "?")")
                if input.isFloat {
                    Button("-", action: onMain(model) { $0.nudgeGraphValue(reference, by: -0.1) })
                        .actionIdentity(ActionID("studio.graph.dec.\(input.name)"))
                    Button("+", action: onMain(model) { $0.nudgeGraphValue(reference, by: 0.1) })
                        .actionIdentity(ActionID("studio.graph.inc.\(input.name)"))
                }
                if input.isEntity {
                    Button("Sel", action: onMain(model) { $0.targetSelection(reference) })
                        .actionIdentity(ActionID("studio.graph.target.\(input.name)"))
                }
            }
            if input.acceptsPending {
                Button("Here", action: onMain(model) { $0.completeLink(to: reference) })
                    .actionIdentity(ActionID("studio.graph.connect.\(input.name)"))
            }
        }
    }
}

#endif

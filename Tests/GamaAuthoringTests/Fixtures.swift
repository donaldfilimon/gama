import GamaAuthoring

/// A session holding `World > [Ground, Character > [Body, Hair]]` plus a
/// root-level `Camera`, built through commands like any real edit.
struct SampleScene {
    var session = EditorSession()
    let world: EntityID
    let ground: EntityID
    let character: EntityID
    let body: EntityID
    let hair: EntityID
    let camera: EntityID
    /// A material graph: `constant (n1) --value--> multiply (n2).a`.
    let graph: GraphID
    let constant: GraphNodeID
    let multiply: GraphNodeID
    /// A second constant (n3), unconnected, for replacing n2.a's feed.
    let spare: GraphNodeID

    init() throws {
        func create(
            _ session: inout EditorSession,
            _ name: String,
            under parent: EntityID?,
            _ components: [Component] = [.transform(.identity)]
        ) throws -> EntityID {
            let id = session.document.nextEntityID
            try session.execute(CreateEntity(name: name, parent: parent, components: components))
            return id
        }
        var session = EditorSession()
        world = try create(&session, "World", under: nil)
        ground = try create(&session, "Ground", under: world, [.transform(.identity), .mesh(.plane)])
        character = try create(&session, "Character", under: world)
        body = try create(&session, "Body", under: character, [.transform(.identity), .mesh(.box), .material(Material())])
        hair = try create(&session, "Hair", under: character, [.transform(.identity), .mesh(.sphere)])
        camera = try create(
            &session, "Camera", under: nil,
            [.transform(.identity), .light(.defaultDirectional), .camera(.default)]
        )
        graph = session.document.nextGraphID
        try session.execute(CreateGraph(name: "Shine", domain: .material))
        constant = GraphNodeID(rawValue: 1)
        try session.execute(AddGraphNode(
            to: graph, definition: "constant.float", inputs: [GraphPort("value", .float)],
            outputs: [GraphPort("value", .float)], values: ["value": .float(0.5)]
        ))
        multiply = GraphNodeID(rawValue: 2)
        try session.execute(AddGraphNode(
            to: graph, definition: "math.multiply",
            inputs: [GraphPort("a", .float), GraphPort("b", .float)],
            outputs: [GraphPort("result", .float)], values: ["b": .float(2)], position: SIMD2(4, 0)
        ))
        try session.execute(ConnectPorts(PortReference(constant, "value"), to: PortReference(multiply, "a"), in: graph))
        spare = GraphNodeID(rawValue: 3)
        try session.execute(AddGraphNode(
            to: graph, definition: "constant.float", inputs: [GraphPort("value", .float)],
            outputs: [GraphPort("value", .float)], values: ["value": .float(9)]
        ))
        _ = session.drainChanges()
        self.session = session
    }
}

func moved(_ x: Float, _ y: Float, _ z: Float) -> Component {
    .transform(Transform(position: SIMD3(x, y, z)))
}

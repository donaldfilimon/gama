import GamaAuthoring

/// Builds documents through commands, as the editor does, so ids and the
/// allocator are realistic (including gaps left by deletion).
struct SceneBuilder {
    var session = EditorSession()

    @discardableResult
    mutating func add(_ name: String, under parent: EntityID? = nil, _ components: [Component] = []) throws -> EntityID {
        let id = session.document.nextEntityID
        try session.execute(CreateEntity(name: name, parent: parent, components: components))
        return id
    }

    var document: SceneDocument { session.document }
}

enum Scenes {
    /// Every component kind, a hierarchy, a deleted id gap, and entities
    /// holding several prim-typed components at once.
    static func everything() throws -> SceneDocument {
        var b = SceneBuilder()
        let world = try b.add("World", [.transform(.identity)])
        try b.add("Ground", under: world, [
            .transform(Transform(scale: SIMD3(10, 1, 10))), .mesh(.plane),
            .material(Material(baseColor: SIMD4(0.5, 0.5, 0.5, 1))),
        ])
        let gap = try b.add("Doomed", under: world)
        try b.session.execute(DeleteEntity(gap))
        try b.add("Box", under: world, [
            .transform(Transform(
                position: SIMD3(-2, 0.5, 0),
                rotation: Rotation(x: 0, y: 0.38268343, z: 0, w: 0.9238795)
            )),
            .mesh(.box),
            .material(Material(baseColor: SIMD4(0.8, 0.2, 0.2, 0.75), metallic: 0.3, roughness: 0.1)),
            .visibility(Visibility(visible: false, locked: true)),
        ])
        try b.add("Sphere", under: world, [.mesh(.sphere), .visibility(Visibility())])
        try b.add("Cylinder", under: world, [.mesh(.cylinder)])
        try b.add("Cone", under: world, [
            .transform(Transform(position: SIMD3(2, 0.1, -0.30000001), scale: SIMD3(-1, 2, 1e-5))),
            .mesh(.cone),
        ])
        try b.add("Sun", [
            .transform(.identity),
            .light(Light(kind: .directional, color: SIMD3(1, 0.9, 0.8), intensity: 3000)),
        ])
        try b.add("Bulb", [.light(.defaultPoint)])
        try b.add("Spot", [.light(Light(
            kind: .spot(innerAngleDegrees: 20, outerAngleDegrees: 45, attenuationRadius: 7.5),
            intensity: 1234.5
        ))])
        try b.add("Camera", [
            .transform(.identity), .light(.defaultDirectional),
            .camera(CameraSettings(fieldOfViewDegrees: 35, near: 0.1, far: 250)),
        ])
        try b.add("Gadget", [
            .mesh(.box), .material(Material()),
            .light(Light(kind: .spot(innerAngleDegrees: 5, outerAngleDegrees: 5, attenuationRadius: 1), intensity: 0)),
            .camera(.default),
        ])
        try b.add("Empty", [])
        return b.document
    }

    /// Hierarchies USD's encapsulation rules constrain: the first root is a
    /// light while materials exist, a mesh holds a mesh, and a light holds
    /// an entity that holds a light. Each must still pass `usdchecker`.
    static func nesting() throws -> SceneDocument {
        var b = SceneBuilder()
        let key = try b.add("Key", [.transform(.identity), .light(.defaultDirectional)])
        let table = try b.add("Table", under: key, [.transform(Transform(position: SIMD3(0, 1, 0))), .mesh(.box), .material(Material())])
        try b.add("Cup", under: table, [.mesh(.cylinder), .material(Material(baseColor: SIMD4(0.1, 0.2, 0.9, 1)))])
        let group = try b.add("Group", under: key)
        try b.add("Fill", under: group, [.light(.defaultPoint)])
        try b.add("Lens", [.camera(.default)])
        return b.document
    }

    /// Two graphs (ADR 0007): a material graph targeting an entity, with a
    /// connection, constants of every storable type, and a deleted node id
    /// gap; and an empty scene graph whose name collides after sanitizing.
    static func graphs() throws -> SceneDocument {
        var b = SceneBuilder()
        let box = try b.add("Box", [.mesh(.box), .material(Material())])
        let g = b.document.nextGraphID
        try b.session.execute(CreateGraph(name: "Rust Look", domain: .material))
        func node(_ definition: String, _ inputs: [GraphPort], _ outputs: [GraphPort], _ values: [String: GraphValue]) throws -> GraphNodeID {
            let id = b.document.graph(g)!.nextNodeID  // just created above
            try b.session.execute(AddGraphNode(to: g, definition: definition, inputs: inputs, outputs: outputs, values: values, position: SIMD2(Float(id.rawValue) * 3, -1.5)))
            return id
        }
        let mix = try node("color.mix", [GraphPort("a", .color), GraphPort("b", .color), GraphPort("t", .float)], [GraphPort("color", .color)],
                           ["a": .color(SIMD4(0, 0, 0, 1)), "b": .color(SIMD4(1, 0.25, 0, 1)), "t": .float(0.3)])
        let gap = try node("constant.float", [], [GraphPort("value", .float)], [:])
        try b.session.execute(RemoveGraphNode(gap, from: g))
        let kitchen = try node("test.everything", [
            GraphPort("f", .float), GraphPort("v2", .vector2), GraphPort("v3", .vector3), GraphPort("v4", .vector4),
            GraphPort("flag", .boolean), GraphPort("count", .integer), GraphPort("label", .string),
            GraphPort("xf", .transform), GraphPort("stuff", .material), GraphPort("nobody", .entity),
            GraphPort("tex", .texture), GraphPort("run", .execution), GraphPort("noise", .custom("noise")),
        ], [GraphPort("out", .custom("noise"))], [
            "f": .float(-0.30000001), "v2": .vector2(SIMD2(1, 2)), "v3": .vector3(SIMD3(1e-5, 2, 3)),
            "v4": .vector4(SIMD4(1, 2, 3, 4)), "flag": .boolean(true), "count": .integer(-42),
            "label": .string("say \"hi\"\n"), "nobody": .entity(nil),
            "xf": .transform(Transform(position: SIMD3(1, 2, 3), rotation: Rotation(x: 0, y: 0.38268343, z: 0, w: 0.9238795), scale: SIMD3(2, 2, 2))),
            "stuff": .material(Material(baseColor: SIMD4(0.1, 0.2, 0.3, 0.4), metallic: 0.5, roughness: 0.6)),
        ])
        _ = kitchen
        let output = try node("output.material", [
            GraphPort("target", .entity), GraphPort("base_color", .color), GraphPort("metallic", .float), GraphPort("roughness", .float),
        ], [], ["target": .entity(box), "metallic": .float(0), "roughness": .float(0.5)])
        try b.session.execute(ConnectPorts(PortReference(mix, "color"), to: PortReference(output, "base_color"), in: g))
        try b.session.execute(CreateGraph(name: "Rust-Look", domain: .scene))
        return b.document
    }

    /// Names that need sanitizing, collide, or hit reserved prim names.
    static func awkwardNames() throws -> SceneDocument {
        var b = SceneBuilder()
        let root = try b.add("Root", [.mesh(.box), .material(Material())])
        for name in ["Café ☕️", "Café ☕️", "", "9lives", "Looks", "GamaMesh", "a\"quote\\slash\nline\u{1}", "Entity"] {
            try b.add(name, under: root)
        }
        try b.add("Root", [])
        return b.document
    }
}

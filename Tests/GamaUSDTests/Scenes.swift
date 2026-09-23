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

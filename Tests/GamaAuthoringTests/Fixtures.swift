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
        camera = try create(&session, "Camera", under: nil)
        _ = session.drainChanges()
        self.session = session
    }
}

func moved(_ x: Float, _ y: Float, _ z: Float) -> Component {
    .transform(Transform(position: SIMD3(x, y, z)))
}

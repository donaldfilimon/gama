import Foundation
import GamaAuthoring
import Testing

@Suite("Document invariants")
struct DocumentInvariantTests {
    @Test func sampleSceneIsValidAndOrdered() throws {
        let scene = try SampleScene()
        let document = scene.session.document
        try document.validate()
        #expect(document.count == 6)
        #expect(document.roots == [scene.world, scene.camera])
        #expect(document.children(of: scene.world) == [scene.ground, scene.character])
        #expect(document.subtree(scene.world) == [scene.world, scene.ground, scene.character, scene.body, scene.hair])
    }

    @Test func identifiersAreSequentialAndDeterministic() throws {
        let first = try SampleScene()
        let second = try SampleScene()
        #expect(first.session.document == second.session.document)
        #expect([first.world, first.ground, first.character, first.body, first.hair, first.camera].map(\.rawValue) == [1, 2, 3, 4, 5, 6])
    }

    @Test func identifiersAreNeverReusedAfterUndo() throws {
        var scene = try SampleScene()
        let next = scene.session.document.nextEntityID
        try scene.session.execute(CreateEntity(name: "Temp"))
        try scene.session.undo()
        try scene.session.execute(CreateEntity(name: "Again"))
        #expect(scene.session.document.contains(next) == false)
        #expect(scene.session.document.roots.last == EntityID(rawValue: next.rawValue + 1))
    }

    @Test func ancestryQuery() throws {
        let scene = try SampleScene()
        let document = scene.session.document
        #expect(document.isSelfOrAncestor(scene.world, of: scene.hair))
        #expect(document.isSelfOrAncestor(scene.hair, of: scene.hair))
        #expect(!document.isSelfOrAncestor(scene.hair, of: scene.world))
        #expect(!document.isSelfOrAncestor(scene.camera, of: scene.body))
    }

    @Test func codableRoundTripPreservesTheDocument() throws {
        // Only the library is standard-library-only; the tests may use
        // Foundation's JSON coder to prove the Codable conformance works.
        var scene = try SampleScene()
        try scene.session.execute(SetComponent(scene.body, .material(Material(metallic: 0.8))))
        let data = try JSONEncoder().encode(scene.session.document)
        let decoded = try JSONDecoder().decode(SceneDocument.self, from: data)
        #expect(decoded == scene.session.document)
        #expect(decoded.nextEntityID == scene.session.document.nextEntityID)
        try decoded.validate()
    }
}

@Suite("Component validation")
struct ComponentValidationTests {
    @Test(arguments: [
        Transform(position: SIMD3(.nan, 0, 0)),
        Transform(scale: SIMD3(1, 0, 1)),
        Transform(scale: SIMD3(1, .infinity, 1)),
        Transform(rotation: Rotation(x: 0, y: 0, z: 0, w: 2)),
        Transform(rotation: Rotation(x: .nan, y: 0, z: 0, w: 1)),
    ])
    func invalidTransformsAreRejected(_ transform: Transform) throws {
        var scene = try SampleScene()
        let before = scene.session.document
        #expect(throws: AuthoringError.self) {
            try scene.session.execute(SetComponent(scene.body, .transform(transform)))
        }
        #expect(scene.session.document == before)
    }

    @Test(arguments: [
        Material(baseColor: SIMD4(1.5, 0, 0, 1)),
        Material(metallic: -0.1),
        Material(roughness: .nan),
    ])
    func invalidMaterialsAreRejected(_ material: Material) throws {
        var scene = try SampleScene()
        #expect(throws: AuthoringError.self) {
            try scene.session.execute(SetComponent(scene.body, .material(material)))
        }
    }

    @Test func invalidComponentOnCreationIsRejected() {
        var session = EditorSession()
        #expect(throws: AuthoringError.self) {
            try session.execute(CreateEntity(name: "Bad", components: [.transform(Transform(scale: .zero))]))
        }
        #expect(session.document.count == 0)
        #expect(session.document.nextEntityID.rawValue == 1)
    }

    @Test func rotationNormalization() {
        #expect(Rotation.identity.isNormalized)
        let half = Float(0.5).squareRoot()
        #expect(Rotation(x: 0, y: half, z: 0, w: half).isNormalized)
        #expect(!Rotation(x: 1, y: 1, z: 0, w: 0).isNormalized)
    }
}

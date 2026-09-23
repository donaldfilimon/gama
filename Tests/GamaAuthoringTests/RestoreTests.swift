import GamaAuthoring
import Testing

@Suite("Restoring a document from records")
struct RestoreTests {
    @Test func restoreReproducesTheDocumentExactly() throws {
        let scene = try SampleScene()
        let original = scene.session.document
        let records = original.entities.values.sorted { $0.id < $1.id }
        let restored = try SceneDocument(
            restoring: records, roots: original.roots, nextEntityID: original.nextEntityID
        )
        #expect(restored == original)
    }

    @Test func restoreRefusesInvalidStructure() throws {
        let scene = try SampleScene()
        let original = scene.session.document
        let records = original.entities.values.sorted { $0.id < $1.id }
        #expect(throws: AuthoringError.duplicateEntity(scene.hair)) {
            try SceneDocument(
                restoring: records + [original.entity(scene.hair)!],
                roots: original.roots, nextEntityID: original.nextEntityID
            )
        }
        // An identifier at or past nextEntityID was never allocated.
        #expect(throws: AuthoringError.self) {
            try SceneDocument(restoring: records, roots: original.roots, nextEntityID: scene.camera)
        }
        // A record no root reaches.
        #expect(throws: AuthoringError.self) {
            try SceneDocument(restoring: records, roots: [scene.world], nextEntityID: original.nextEntityID)
        }
        let orphanChild = EntityRecord(id: EntityID(rawValue: 1), name: "A", parent: EntityID(rawValue: 2))
        #expect(throws: AuthoringError.self) {
            try SceneDocument(restoring: [orphanChild], roots: [orphanChild.id], nextEntityID: EntityID(rawValue: 3))
        }
        let badMaterial = EntityRecord(
            id: EntityID(rawValue: 1), name: "B",
            components: [.material: .material(Material(roughness: 2))]
        )
        #expect(throws: AuthoringError.self) {
            try SceneDocument(restoring: [badMaterial], roots: [badMaterial.id], nextEntityID: EntityID(rawValue: 2))
        }
    }
}

import GamaAuthoring
import Testing

@Suite("Hierarchy")
struct HierarchyTests {
    @Test func deleteSubtreeAndUndoRestoresOrderAndComponents() throws {
        var scene = try SampleScene()
        let before = scene.session.document
        try scene.session.execute(DeleteEntity(scene.character))
        #expect(scene.session.document.count == 3)
        #expect(!scene.session.document.contains(scene.body))
        try scene.session.undo()
        #expect(scene.session.document.hasSameContent(as: before))
        #expect(scene.session.document.children(of: scene.world) == [scene.ground, scene.character])
    }

    @Test func reparentAppendsByDefault() throws {
        var scene = try SampleScene()
        try scene.session.execute(ReparentEntity(scene.camera, to: scene.character))
        #expect(scene.session.document.children(of: scene.character) == [scene.body, scene.hair, scene.camera])
        #expect(scene.session.document.roots == [scene.world])
    }

    @Test func reorderIndexIsAfterRemoval() throws {
        var scene = try SampleScene()
        try scene.session.execute(ReparentEntity(scene.body, to: scene.character, at: 1))
        #expect(scene.session.document.children(of: scene.character) == [scene.hair, scene.body])
        try scene.session.undo()
        #expect(scene.session.document.children(of: scene.character) == [scene.body, scene.hair])
    }

    @Test func descendantCannotBecomeParent() throws {
        var scene = try SampleScene()
        #expect(throws: AuthoringError.wouldCreateCycle(entity: scene.world, parent: scene.body)) {
            try scene.session.execute(ReparentEntity(scene.world, to: scene.body))
        }
    }

    @Test func outOfRangeIndexIsRefused() throws {
        var scene = try SampleScene()
        #expect(throws: AuthoringError.invalidIndex(5, count: 1)) {
            try scene.session.execute(ReparentEntity(scene.body, to: scene.character, at: 5))
        }
        #expect(throws: AuthoringError.invalidIndex(-1, count: 2)) {
            try scene.session.execute(CreateEntity(name: "x", parent: scene.world, index: -1))
        }
    }
}

@Suite("Duplication")
struct DuplicateTests {
    @Test func duplicateCopiesStructureWithFreshIdentifiers() throws {
        var scene = try SampleScene()
        let firstNew = scene.session.document.nextEntityID
        try scene.session.execute(DuplicateEntity(scene.character))
        let document = scene.session.document
        let copy = firstNew
        #expect(document.children(of: scene.world) == [scene.ground, scene.character, copy])
        let copies = document.subtree(copy)
        #expect(copies.count == 3)
        #expect(Set(copies).isDisjoint(with: document.subtree(scene.character)))
        #expect(copies.map { document.entity($0)?.name } == ["Character", "Body", "Hair"])
        #expect(document.entity(copies[1])?.components == document.entity(scene.body)?.components)
        #expect(document.entity(copies[1])?.parent == copy)
        try document.validate()
    }

    @Test func duplicateOfRootLandsNextToIt() throws {
        var scene = try SampleScene()
        let copy = scene.session.document.nextEntityID
        try scene.session.execute(DuplicateEntity(scene.world))
        #expect(scene.session.document.roots == [scene.world, copy, scene.camera])
    }
}

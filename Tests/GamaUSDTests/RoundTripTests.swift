import GamaAuthoring
import GamaUSD
import Testing

@Suite("USDA round trips")
struct RoundTripTests {
    func roundTrip(_ document: SceneDocument) throws -> SceneDocument {
        try sceneDocument(fromUSDA: usdaString(from: document))
    }

    @Test func everyComponentKindSurvivesExactly() throws {
        let document = try Scenes.everything()
        #expect(try roundTrip(document) == document)
    }

    @Test func awkwardNamesSurviveExactly() throws {
        let document = try Scenes.awkwardNames()
        #expect(try roundTrip(document) == document)
    }

    @Test func nestedHierarchiesSurviveExactly() throws {
        let document = try Scenes.nesting()
        #expect(try roundTrip(document) == document)
    }

    /// USD forbids a gprim inside a gprim, and anything but a connectable
    /// prim under a light, so such entities become an Xform holding their
    /// mesh or light as a component child.
    @Test func entitiesWithChildPrimsMoveTheirTypeIntoAComponentChild() throws {
        let text = usdaString(from: try Scenes.nesting())
        #expect(text.contains("def Xform \"Key\"\n"))
        #expect(text.contains("def DistantLight \"GamaLight\""))
        #expect(text.contains("def Xform \"Table\" (\n        prepend apiSchemas = [\"MaterialBindingAPI\"]\n    )"))
        #expect(text.contains("def Cube \"GamaMesh\""))
        // Childless entities stay inline, including the leaf light and mesh.
        #expect(text.contains("def Cylinder \"Cup\""))
        #expect(text.contains("def SphereLight \"Fill\""))
        #expect(text.contains("def Camera \"Lens\""))
        // The material library sits under the Xform first root, not a light.
        #expect(text.contains("rel material:binding = </Key/Looks/M_2>"))
    }

    @Test func aLightFirstRootWithoutMaterialsStaysInline() throws {
        var b = SceneBuilder()
        try b.add("Sun", [.light(.defaultDirectional)])
        try b.add("Box", [.mesh(.box)])
        #expect(usdaString(from: b.document).contains("def DistantLight \"Sun\""))
    }

    @Test func emptyDocumentSurvives() throws {
        let document = SceneDocument()
        #expect(try roundTrip(document) == document)
    }

    @Test(arguments: Primitive.allCases)
    func everyPrimitiveSurvives(_ primitive: Primitive) throws {
        var b = SceneBuilder()
        try b.add("P", [.mesh(primitive)])
        #expect(try roundTrip(b.document) == b.document)
    }

    @Test func combinedComponentsBecomeChildPrimsAndFoldBack() throws {
        var b = SceneBuilder()
        let id = try b.add("Rig", [.transform(.identity), .light(.defaultDirectional), .camera(.default)])
        let text = usdaString(from: b.document)
        #expect(text.contains("def Xform \"Rig\""))
        #expect(text.contains("def DistantLight \"GamaLight\""))
        #expect(text.contains("def Camera \"GamaCamera\""))
        let read = try sceneDocument(fromUSDA: text)
        #expect(read == b.document)
        #expect(read.entity(id)?.children == [])
        #expect(read.count == 1)
    }

    @Test func singleTypedComponentsStayInline() throws {
        var b = SceneBuilder()
        try b.add("Box", [.mesh(.box)])
        try b.add("Lamp", [.light(Light(
            kind: .spot(innerAngleDegrees: 10, outerAngleDegrees: 30, attenuationRadius: 5), intensity: 10
        ))])
        let text = usdaString(from: b.document)
        #expect(text.contains("def Cube \"Box\""))
        #expect(text.contains("def SphereLight \"Lamp\" (\n    prepend apiSchemas = [\"ShapingAPI\"]\n)"))
        #expect(!text.contains("GamaMesh"))
    }

    @Test func writerIsDeterministic() throws {
        let document = try Scenes.everything()
        #expect(usdaString(from: document) == usdaString(from: document))
        #expect(usdaString(from: try roundTrip(document)) == usdaString(from: document))
    }

    @Test func reservedAndCollidingNamesGetSuffixes() throws {
        let text = usdaString(from: try Scenes.awkwardNames())
        let expected = [
            "Caf____", "Caf_____3", "Entity", "_9lives", "Looks_6", "GamaMesh_7",
            "a_quote_slash_line_", "Entity_9", "Root_10",
        ]
        for name in expected {
            #expect(text.contains("def Xform \"\(name)\"\n"), "missing prim \(name)")
        }
        // The first root keeps its name and holds the material library.
        // It has children, so its box moves into a component child.
        #expect(text.contains("def Xform \"Root\" (\n    prepend apiSchemas = [\"MaterialBindingAPI\"]\n)"))
        #expect(text.contains("rel material:binding = </Root/Looks/M_1>"))
    }

    @Test func standardSchemasCarryPreviewValues() throws {
        var b = SceneBuilder()
        try b.add("Cam", [.camera(CameraSettings(fieldOfViewDegrees: 90, near: 0.5, far: 50))])
        let text = usdaString(from: b.document)
        // 90° over a 24 mm aperture: 12 / tan(45°) = 12 mm.
        #expect(text.contains("float focalLength = 12\n"))
        #expect(text.contains("float2 clippingRange = (0.5, 50)"))
        #expect(text.contains("custom float gama:fieldOfView = 90"))
    }
}

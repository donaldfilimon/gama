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
        #expect(text.contains("def Cube \"Root\" (\n    prepend apiSchemas = [\"MaterialBindingAPI\"]\n)"))
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

import GamaAuthoring
import GamaUSD
import Testing

/// The reader never skips what it does not understand: each refusal names the
/// line it stopped at.
@Suite("USDA refusals")
struct RefusalTests {
    static let header = """
    #usda 1.0
    (
        customLayerData = {
            int "gama:formatVersion" = 1
            uint64 "gama:nextEntityID" = 5
        }
    )

    """

    func read(_ body: String) throws(USDError) -> SceneDocument {
        try sceneDocument(fromUSDA: Self.header + body)
    }

    @Test func missingHeaderIsASyntaxError() {
        #expect(throws: USDError.syntax(line: 1, "expected a '#usda 1.0' header")) {
            try sceneDocument(fromUSDA: "def Xform \"A\" {}")
        }
    }

    @Test func missingFormatVersionIsUnsupported() {
        #expect(throws: USDError.unsupported(line: 1, "missing gama:formatVersion; not a Gama Studio file")) {
            try sceneDocument(fromUSDA: "#usda 1.0\ndef Xform \"A\"\n{\n}\n")
        }
    }

    @Test func otherFormatVersionIsUnsupported() {
        let text = "#usda 1.0\n(\n    customLayerData = {\n        int \"gama:formatVersion\" = 2\n    }\n)\n"
        #expect(throws: USDError.unsupported(line: 1, "gama:formatVersion 2 is not supported by this reader")) {
            try sceneDocument(fromUSDA: text)
        }
    }

    @Test func unknownPrimTypeNamesItsLine() {
        let body = """
        def Mesh "Blob"
        {
            custom uint64 gama:id = 1
        }
        """
        #expect(throws: USDError.unsupported(line: 8, "prim type 'Mesh' on 'Blob'")) { try read(body) }
    }

    @Test func badNumberNamesItsLine() {
        let body = """
        def Xform "A"
        {
            custom uint64 gama:id = 1
            float3 xformOp:translate = (1, two, 3)
        }
        """
        #expect(throws: USDError.syntax(line: 11, "expected a number")) { try read(body) }
    }

    @Test func duplicateIdentifierNamesBothLines() {
        let body = """
        def Xform "A"
        {
            custom uint64 gama:id = 1
        }

        def Xform "B"
        {
            custom uint64 gama:id = 1
        }
        """
        #expect(throws: USDError.syntax(line: 15, "gama:id 1 already used on line 10")) { try read(body) }
    }

    @Test func missingIdentifierIsUnsupported() {
        #expect(throws: USDError.unsupported(line: 8, "prim 'A' has no gama:id")) {
            try read("def Xform \"A\"\n{\n}\n")
        }
    }

    @Test func animatedAttributesAreUnsupported() {
        let body = """
        def Xform "A"
        {
            custom uint64 gama:id = 1
            float3 xformOp:translate.timeSamples = {
                0: (0, 0, 0),
            }
        }
        """
        #expect(throws: USDError.unsupported(line: 11, "animated attribute 'xformOp:translate.timeSamples'")) {
            try read(body)
        }
    }

    @Test func invalidDocumentIsRefusedAsInvalid() {
        // Parses cleanly, but the identifier was never allocated (>= next).
        let body = """
        def Xform "A"
        {
            custom uint64 gama:id = 9
        }
        """
        #expect(throws: USDError.self) { try read(body) }
        do {
            _ = try read(body)
        } catch {
            guard case .invalid = error else {
                Issue.record("expected .invalid, got \(error)")
                return
            }
        }
    }

    @Test func outOfRangeMaterialIsRefusedAsInvalid() {
        let body = """
        def Cube "A" (prepend apiSchemas = ["MaterialBindingAPI"])
        {
            custom uint64 gama:id = 1
            rel material:binding = </A/Looks/M_1>
            def Scope "Looks"
            {
                def Material "M_1"
                {
                    def Shader "Surface"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        float inputs:roughness = 2
                    }
                }
            }
        }
        """
        #expect(throws: USDError.invalid(.invariantViolated("#1 holds an invalid material: invalidMaterial(\"roughness must be in 0...1\")"))) {
            try read(body)
        }
    }

    @Test func danglingMaterialBindingNamesItsLine() {
        let body = """
        def Cube "A"
        {
            custom uint64 gama:id = 1
            rel material:binding = </Nowhere>
        }
        """
        #expect(throws: USDError.syntax(line: 11, "material:binding targets </Nowhere>, which is not a Material")) {
            try read(body)
        }
    }

    @Test func compositionIsRefusedNotDropped() {
        let referenced = """
        def Xform "A" (
            references = @other.usda@</B>
        )
        {
            custom uint64 gama:id = 1
        }
        """
        #expect(throws: USDError.unsupported(line: 8, "references on 'A'")) { try read(referenced) }
        let over = """
        def Xform "A"
        {
            custom uint64 gama:id = 1
            over "B"
            {
            }
        }
        """
        #expect(throws: USDError.unsupported(line: 11, "'over' prim 'B'")) { try read(over) }
        let layered = "#usda 1.0\n(\n    subLayers = [@base.usda@]\n    customLayerData = {\n        int \"gama:formatVersion\" = 1\n    }\n)\n"
        #expect(throws: USDError.unsupported(line: 1, "layer subLayers")) { try sceneDocument(fromUSDA: layered) }
    }

    @Test func identifiersAtTheLimitAreRefusedNotTrapped() {
        let maxID = "def Xform \"A\"\n{\n    custom uint64 gama:id = 18446744073709551615\n}\n"
        #expect(throws: USDError.syntax(line: 10, "gama:id must be in 1..<18446744073709551615")) { try read(maxID) }
        let full = "#usda 1.0\n(\n    customLayerData = {\n        int \"gama:formatVersion\" = 1\n        uint64 \"gama:nextEntityID\" = 18446744073709551615\n    }\n)\n"
        #expect(throws: USDError.unsupported(line: 1, "gama:nextEntityID leaves no identifiers to allocate")) {
            try sceneDocument(fromUSDA: full)
        }
    }

    @Test func usdEscapesAndReorderStatementsRead() throws {
        let body = """
        def Xform "A"
        {
            reorder properties = ["gama:name", "gama:id"]
            custom uint64 gama:id = 1
            custom string gama:name = "\\a\\b\\f\\v\\0\\101\\x42"
        }
        """
        let document = try read(body)
        #expect(document.entity(EntityID(rawValue: 1))?.name == "\u{7}\u{8}\u{C}\u{B}\u{0}AB")
    }

    @Test func unterminatedPrimIsASyntaxError() {
        #expect(throws: USDError.self) { try read("def Xform \"A\"\n{\n    custom uint64 gama:id = 1\n") }
    }
}

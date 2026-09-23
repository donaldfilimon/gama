public import GamaAuthoring

/// Serializes `document` as USDA text (ADR 0005).
///
/// Output is deterministic byte for byte: prims follow the authored order of
/// roots and children, and properties follow ``ComponentKind`` order, so equal
/// documents always produce identical text. Standard schemas (UsdGeom gprims,
/// UsdPreviewSurface, UsdLux, UsdGeomCamera) keep the file useful to other USD
/// tools; `gama:` attributes carry the values Gama reads back exactly.
public func usdaString(from document: SceneDocument) -> String {
    var writer = USDAWriter(document: document)
    return writer.write()
}

private struct USDAWriter {
    let document: SceneDocument
    var output = ""
    /// Prim name per entity, decided up front so material bindings can name
    /// paths before those prims are written.
    var primNames: [EntityID: String] = [:]
    var looksPath = ""
    /// Every entity holding a material, in document order; the `Looks` scope
    /// is written only when this is non-empty.
    var materials: [(EntityID, Material)] = []

    init(document: SceneDocument) {
        self.document = document
    }

    mutating func write() -> String {
        assignNames(document.roots)
        for id in document.roots {
            for descendant in document.subtree(id) {
                assignNames(document.children(of: descendant))
            }
        }
        if let first = document.roots.first, let name = primNames[first] {
            looksPath = "/\(name)/\(USDSchema.looksScope)"
        }
        for root in document.roots {
            for id in document.subtree(root) {
                if case .material(let material)? = document.component(.material, of: id) {
                    materials.append((id, material))
                }
            }
        }

        let hasGraphs = !document.graphOrder.isEmpty || document.nextGraphID.rawValue > 1
        output += "#usda 1.0\n(\n"
        output += "    customLayerData = {\n"
        let version = hasGraphs ? USDSchema.graphFormatVersion : USDSchema.formatVersion
        output += "        int \"\(USDSchema.formatVersionKey)\" = \(version)\n"
        output += "        uint64 \"\(USDSchema.nextEntityIDKey)\" = \(document.nextEntityID.rawValue)\n"
        if hasGraphs {
            output += "        uint64 \"\(USDSchema.nextGraphIDKey)\" = \(document.nextGraphID.rawValue)\n"
        }
        output += "    }\n"
        if let first = document.roots.first, let name = primNames[first] {
            output += "    defaultPrim = \(quoted(name))\n"
        } else if !document.graphOrder.isEmpty {
            output += "    defaultPrim = \(quoted(USDSchema.graphLibrary))\n"
        }
        output += "    metersPerUnit = 1\n"
        output += "    upAxis = \"Y\"\n"
        output += ")\n"
        for (index, id) in document.roots.enumerated() {
            output += "\n"
            writeEntity(id, depth: 0, holdsLooks: index == 0 && !materials.isEmpty)
        }
        if !document.graphOrder.isEmpty {
            output += "\n"
            writeGraphs()
        }
        return output
    }

    // MARK: Names

    /// Gives each sibling a valid, unique USD prim name: the sanitized entity
    /// name, or that name plus `_<id>` when it is reserved or already taken.
    mutating func assignNames(_ siblings: [EntityID]) {
        var used: Set<String> = USDSchema.reservedNames
        for id in siblings {
            let base = sanitize(document.entity(id)?.name ?? "")
            var candidate = base
            while used.contains(candidate) {
                candidate += "_\(id.rawValue)"
            }
            used.insert(candidate)
            primNames[id] = candidate
        }
    }

    func sanitize(_ name: String) -> String {
        var result = ""
        for scalar in name.unicodeScalars {
            let isLetter = ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
            let isDigit = ("0"..."9").contains(scalar)
            if isLetter || (isDigit && !result.isEmpty) {
                result.unicodeScalars.append(scalar)
            } else if isDigit {
                result += "_"
                result.unicodeScalars.append(scalar)
            } else {
                result += "_"
            }
        }
        return result.isEmpty ? "Entity" : result
    }

    // MARK: Prims

    mutating func writeEntity(_ id: EntityID, depth: Int, holdsLooks: Bool) {
        guard let record = document.entity(id), let name = primNames[id] else { return }
        let components = record.components
        var primTyped: [ComponentKind] = []
        for kind in [ComponentKind.mesh, .light, .camera] where components[kind] != nil {
            primTyped.append(kind)
        }
        // A lone mesh, light, or camera is written as the entity prim itself,
        // unless that would nest prims USD forbids: a gprim may not contain
        // another gprim, and a light's descendants must all be connectable,
        // which neither an Xform child nor the Looks scope is. Those entities
        // become an Xform with a component child instead (ADR 0005).
        var inline: ComponentKind? = primTyped.count == 1 ? primTyped[0] : nil
        if !record.children.isEmpty || (holdsLooks && inline == .light) {
            inline = nil
        }
        let typeName = inline.map { primTypeName(components[$0]!) } ?? "Xform"

        var schemas: [String] = []
        if components[.material] != nil { schemas.append("MaterialBindingAPI") }
        if inline == .light, case .light(let light)? = components[.light], case .spot = light.kind {
            schemas.append("ShapingAPI")
        }

        let indent = String(repeating: "    ", count: depth)
        output += "\(indent)def \(typeName) \(quoted(name))"
        if !schemas.isEmpty {
            output += " (\n\(indent)    prepend apiSchemas = [\(schemas.map(quoted).joined(separator: ", "))]\n\(indent))"
        }
        output += "\n\(indent){\n"
        let body = depth + 1
        line(body, "custom uint64 \(USDSchema.idAttribute) = \(id.rawValue)")
        line(body, "custom string \(USDSchema.nameAttribute) = \(quoted(record.name))")

        for kind in ComponentKind.allCases.sorted() {
            guard let component = components[kind] else { continue }
            switch component {
            case .transform(let transform):
                writeTransform(transform, depth: body)
            case .material:
                line(body, "rel material:binding = <\(looksPath)/M_\(id.rawValue)>")
            case .visibility(let visibility):
                if !visibility.visible { line(body, "token visibility = \"invisible\"") }
                line(body, "custom bool \(USDSchema.visibleAttribute) = \(bool(visibility.visible))")
                line(body, "custom bool \(USDSchema.lockedAttribute) = \(bool(visibility.locked))")
            case .mesh, .light, .camera:
                if kind == inline { writeAttributes(of: component, depth: body) }
            }
        }

        for kind in primTyped where kind != inline {
            writeComponentChild(components[kind]!, depth: body)
        }
        for child in record.children {
            writeEntity(child, depth: body, holdsLooks: false)
        }
        if holdsLooks { writeLooks(depth: body) }
        output += "\(indent)}\n"
    }

    /// A component that shares its entity with another prim-typed component,
    /// written as a child prim the reader folds back into the entity.
    mutating func writeComponentChild(_ component: Component, depth: Int) {
        let name: String
        switch component.kind {
        case .mesh: name = USDSchema.meshChild
        case .light: name = USDSchema.lightChild
        default: name = USDSchema.cameraChild
        }
        let indent = String(repeating: "    ", count: depth)
        output += "\(indent)def \(primTypeName(component)) \(quoted(name))"
        if case .light(let light) = component, case .spot = light.kind {
            output += " (\n\(indent)    prepend apiSchemas = [\"ShapingAPI\"]\n\(indent))"
        }
        output += "\n\(indent){\n"
        line(depth + 1, "custom bool \(USDSchema.componentAttribute) = 1")
        writeAttributes(of: component, depth: depth + 1)
        output += "\(indent)}\n"
    }

    func primTypeName(_ component: Component) -> String {
        switch component {
        case .mesh(let primitive): USDSchema.typeName(for: primitive)
        case .light(let light): USDSchema.typeName(for: light.kind)
        default: USDSchema.cameraTypeName
        }
    }

    mutating func writeAttributes(of component: Component, depth: Int) {
        switch component {
        case .mesh(let primitive):
            switch primitive {
            case .box:
                line(depth, "double size = 1")
            case .sphere:
                line(depth, "double radius = 0.5")
            case .cylinder, .cone:
                line(depth, "uniform token axis = \"Y\"")
                line(depth, "double height = 1")
                line(depth, "double radius = 0.5")
            case .plane:
                line(depth, "uniform token axis = \"Y\"")
                line(depth, "double length = 1")
                line(depth, "double width = 1")
            }
        case .light(let light):
            line(depth, "color3f inputs:color = \(tuple(light.color.x, light.color.y, light.color.z))")
            line(depth, "float inputs:intensity = \(number(light.intensity / USDSchema.previewIntensityDivisor))")
            line(depth, "custom float \(USDSchema.intensityAttribute) = \(number(light.intensity))")
            switch light.kind {
            case .directional:
                break
            case .point(let radius):
                line(depth, "bool treatAsPoint = 1")
                line(depth, "custom float \(USDSchema.attenuationRadiusAttribute) = \(number(radius))")
            case .spot(let inner, let outer, let radius):
                line(depth, "float inputs:shaping:cone:angle = \(number(outer / 2))")
                line(depth, "float inputs:shaping:cone:softness = \(number(1 - inner / outer))")
                line(depth, "bool treatAsPoint = 1")
                line(depth, "custom float \(USDSchema.attenuationRadiusAttribute) = \(number(radius))")
                line(depth, "custom float \(USDSchema.innerAngleAttribute) = \(number(inner))")
                line(depth, "custom float \(USDSchema.outerAngleAttribute) = \(number(outer))")
            }
        case .camera(let camera):
            line(depth, "float2 clippingRange = \(tuple(camera.near, camera.far))")
            line(depth, "float focalLength = \(number(focalLength(fieldOfViewDegrees: camera.fieldOfViewDegrees)))")
            line(depth, "float verticalAperture = \(number(USDSchema.verticalAperture))")
            line(depth, "custom float \(USDSchema.fieldOfViewAttribute) = \(number(camera.fieldOfViewDegrees))")
        default:
            break
        }
    }

    mutating func writeTransform(_ transform: Transform, depth: Int) {
        let p = transform.position, r = transform.rotation, s = transform.scale
        line(depth, "float3 xformOp:translate = \(tuple(p.x, p.y, p.z))")
        // USD quaternions are written real part first.
        line(depth, "quatf xformOp:orient = \(tuple(r.w, r.x, r.y, r.z))")
        line(depth, "float3 xformOp:scale = \(tuple(s.x, s.y, s.z))")
        line(depth, "uniform token[] xformOpOrder = [\"xformOp:translate\", \"xformOp:orient\", \"xformOp:scale\"]")
    }

    /// The material library: one UsdPreviewSurface material per entity that
    /// holds a material, in document order.
    mutating func writeLooks(depth: Int) {
        let indent = String(repeating: "    ", count: depth)
        output += "\(indent)def Scope \(quoted(USDSchema.looksScope))\n\(indent){\n"
        for (id, material) in materials {
            let name = "M_\(id.rawValue)"
            let path = "\(looksPath)/\(name)"
            let m = String(repeating: "    ", count: depth + 1)
            output += "\(m)def Material \(quoted(name))\n\(m){\n"
            line(depth + 2, "token outputs:surface.connect = <\(path)/\(USDSchema.shaderName).outputs:surface>")
            let s = String(repeating: "    ", count: depth + 2)
            output += "\(s)def Shader \(quoted(USDSchema.shaderName))\n\(s){\n"
            let c = material.baseColor
            line(depth + 3, "uniform token info:id = \"UsdPreviewSurface\"")
            line(depth + 3, "color3f inputs:diffuseColor = \(tuple(c.x, c.y, c.z))")
            line(depth + 3, "float inputs:metallic = \(number(material.metallic))")
            line(depth + 3, "float inputs:opacity = \(number(c.w))")
            line(depth + 3, "float inputs:roughness = \(number(material.roughness))")
            line(depth + 3, "token outputs:surface")
            output += "\(s)}\n\(m)}\n"
        }
        output += "\(indent)}\n"
    }

    // MARK: Graphs

    /// The graph library (ADR 0007): one `NodeGraph` per graph under a root
    /// `Scope`, one typeless prim per node named by its id (`n3`), port
    /// signatures as `name:type` string arrays, constants as typed
    /// `gama:value:<input>` attributes, and connections as
    /// `gama:link:<input> = "n2.<output>"`.
    mutating func writeGraphs() {
        output += "def Scope \(quoted(USDSchema.graphLibrary))\n{\n"
        line(1, "custom bool \(USDSchema.graphLibraryAttribute) = 1")
        var used: Set<String> = []
        for id in document.graphOrder {
            guard let graph = document.graph(id) else { continue }
            var name = sanitize(graph.name)
            while used.contains(name) { name += "_\(id.rawValue)" }
            used.insert(name)
            output += "    def NodeGraph \(quoted(name))\n    {\n"
            line(2, "custom uint64 \(USDSchema.graphIDAttribute) = \(id.rawValue)")
            line(2, "custom string \(USDSchema.nameAttribute) = \(quoted(graph.name))")
            line(2, "custom token \(USDSchema.graphDomainAttribute) = \(quoted(graph.domain.rawValue))")
            line(2, "custom uint64 \(USDSchema.nextNodeIDAttribute) = \(graph.nextNodeID.rawValue)")
            for nodeID in graph.order {
                guard let node = graph.node(nodeID) else { continue }
                output += "        def \(quoted(nodeID.description))\n        {\n"
                line(3, "custom string \(USDSchema.definitionAttribute) = \(quoted(node.definition))")
                line(3, "custom float2 \(USDSchema.positionAttribute) = \(tuple(node.position.x, node.position.y))")
                line(3, "custom string[] \(USDSchema.inputsAttribute) = \(signature(node.inputs))")
                line(3, "custom string[] \(USDSchema.outputsAttribute) = \(signature(node.outputs))")
                for port in node.inputs {
                    if let value = node.values[port.name] {
                        line(3, graphValue(value, named: USDSchema.valuePrefix + port.name))
                    }
                    if let link = graph.connection(into: PortReference(nodeID, port.name)) {
                        line(3, "custom string \(USDSchema.linkPrefix)\(port.name) = \(quoted(link.from.description))")
                    }
                }
                output += "        }\n"
            }
            output += "    }\n"
        }
        output += "}\n"
    }

    func signature(_ ports: [GraphPort]) -> String {
        "[" + ports.map { quoted("\($0.name):\($0.type)") }.joined(separator: ", ") + "]"
    }

    func graphValue(_ value: GraphValue, named name: String) -> String {
        func floats(_ values: [Float]) -> String { "[" + values.map(number).joined(separator: ", ") + "]" }
        switch value {
        case .float(let v): return "custom float \(name) = \(number(v))"
        case .vector2(let v): return "custom float2 \(name) = \(tuple(v.x, v.y))"
        case .vector3(let v): return "custom float3 \(name) = \(tuple(v.x, v.y, v.z))"
        case .vector4(let v): return "custom float4 \(name) = \(tuple(v.x, v.y, v.z, v.w))"
        case .color(let v): return "custom color4f \(name) = \(tuple(v.x, v.y, v.z, v.w))"
        case .boolean(let v): return "custom bool \(name) = \(bool(v))"
        case .integer(let v): return "custom int64 \(name) = \(v)"
        case .string(let v): return "custom string \(name) = \(quoted(v))"
        case .entity(let v): return "custom uint64 \(name) = \(v?.rawValue ?? 0)"
        case .transform(let t):
            let p = t.position, r = t.rotation, s = t.scale
            // Position, rotation (real part first, as xformOp:orient), scale.
            return "custom float[] \(name) = " + floats([p.x, p.y, p.z, r.w, r.x, r.y, r.z, s.x, s.y, s.z])
        case .material(let m):
            let c = m.baseColor
            return "custom float[] \(name) = " + floats([c.x, c.y, c.z, c.w, m.metallic, m.roughness])
        }
    }

    // MARK: Formatting

    mutating func line(_ depth: Int, _ text: String) {
        output += String(repeating: "    ", count: depth) + text + "\n"
    }
}

/// Shortest text that reads back as the same `Float`, with `.0` dropped so
/// integral values look like USD's own output.
func number(_ value: Float) -> String {
    let text = value.description
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
}

func tuple(_ values: Float...) -> String {
    "(" + values.map(number).joined(separator: ", ") + ")"
}

func bool(_ value: Bool) -> String { value ? "1" : "0" }

/// A USDA string literal. Quotes, backslashes, and control characters are
/// escaped; everything else, including non-ASCII text, is written as is.
func quoted(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        default:
            if scalar.value < 0x20 || scalar.value == 0x7F {
                let hex = String(scalar.value, radix: 16, uppercase: true)
                result += "\\x" + (hex.count == 1 ? "0" + hex : hex)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }
    return result + "\""
}

/// The focal length, in millimetres, that gives `fieldOfViewDegrees`
/// vertically over ``USDSchema/verticalAperture``. Computed here because the
/// standard library has no trigonometry and this target stays stdlib-only.
func focalLength(fieldOfViewDegrees: Float) -> Float {
    let half = Double(fieldOfViewDegrees) * Double.pi / 360
    return Float(Double(USDSchema.verticalAperture) / 2 * cosine(half) / sine(half))
}

/// Taylor series, accurate to well below `Float` precision on `0...π/2`,
/// the only range ``focalLength(fieldOfViewDegrees:)`` needs.
func sine(_ x: Double) -> Double {
    var term = x, sum = x
    for n in 1...12 {
        term *= -x * x / Double((2 * n) * (2 * n + 1))
        sum += term
    }
    return sum
}

func cosine(_ x: Double) -> Double {
    var term = 1.0, sum = 1.0
    for n in 1...12 {
        term *= -x * x / Double((2 * n - 1) * (2 * n))
        sum += term
    }
    return sum
}

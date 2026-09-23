public import GamaAuthoring

/// Reads USDA that ``usdaString(from:)`` wrote, including the same content
/// after another USD tool (such as `usdcat`) reformatted it (ADR 0005).
///
/// Identifiers, names, and component values come back exactly. Every prim
/// type outside Gama's subset is refused with its line, never skipped, and the
/// result must pass ``SceneDocument/validate()``. Properties Gama does not
/// read (such as `extent`) are ignored.
public func sceneDocument(fromUSDA text: String) throws(USDError) -> SceneDocument {
    let layer = try parseUSDA(text)
    var reader = USDAReader()
    return try reader.read(layer)
}

private struct USDAReader {
    var records: [EntityRecord] = []
    var seen: [EntityID: Int] = [:]
    /// Material prims by absolute path.
    var materials: [String: USDAPrim] = [:]

    mutating func read(_ layer: USDALayer) throws(USDError) -> SceneDocument {
        guard case .dictionary(let data)? = layer.metadata["customLayerData"],
              let version = data[USDSchema.formatVersionKey]
        else {
            throw .unsupported(line: 1, "missing \(USDSchema.formatVersionKey); not a Gama Studio file")
        }
        let found = try integer(version, line: 1)
        guard USDSchema.supportedVersions.contains(found) else {
            throw .unsupported(line: 1, "\(USDSchema.formatVersionKey) \(found) is not supported by this reader")
        }

        for key in ["subLayers", "relocates"] where layer.metadata[key] != nil {
            throw .unsupported(line: 1, "layer \(key)")
        }
        for prim in layer.prims {
            try refuseComposition(prim)
            collectMaterials(prim, path: "")
        }
        var roots: [EntityID] = []
        var graphs: [GraphDocument] = []
        for prim in layer.prims {
            if prim.typeName == "Scope", prim.property(USDSchema.graphLibraryAttribute) != nil {
                guard found >= UInt64(USDSchema.graphFormatVersion) else {
                    throw .unsupported(line: prim.line, "a graph library needs \(USDSchema.formatVersionKey) 2")
                }
                for child in prim.children {
                    graphs.append(try graph(child))
                }
                continue
            }
            roots.append(try entity(prim, parent: nil))
        }
        var nextGraph: GraphID?
        if let value = data[USDSchema.nextGraphIDKey] {
            let raw = try integer(value, line: 1)
            guard raw < UInt64.max else {
                throw .unsupported(line: 1, "\(USDSchema.nextGraphIDKey) leaves no identifiers to allocate")
            }
            nextGraph = GraphID(rawValue: raw)
        }

        let next: EntityID
        if let value = data[USDSchema.nextEntityIDKey] {
            let raw = try integer(value, line: 1)
            // The allocator hands out `next` and then increments it.
            guard raw < UInt64.max else {
                throw .unsupported(line: 1, "\(USDSchema.nextEntityIDKey) leaves no identifiers to allocate")
            }
            next = EntityID(rawValue: raw)
        } else {
            next = EntityID(rawValue: (records.map(\.id.rawValue).max() ?? 0) + 1)
        }
        do {
            return try SceneDocument(
                restoring: records, roots: roots, nextEntityID: next, graphs: graphs, nextGraphID: nextGraph
            )
        } catch {
            throw .invalid(error)
        }
    }

    // MARK: Graphs

    /// One `NodeGraph` from the graph library (ADR 0007).
    func graph(_ prim: USDAPrim) throws(USDError) -> GraphDocument {
        guard prim.typeName == "NodeGraph" else {
            throw .unsupported(line: prim.line, "'\(prim.name)' in the graph library is not a NodeGraph")
        }
        let idProperty = try required(prim, USDSchema.graphIDAttribute)
        let raw = try integer(idProperty.value ?? .word("None"), line: idProperty.line)
        guard raw > 0, raw < UInt64.max else { throw .syntax(line: idProperty.line, "graph id out of range") }
        let name = try string(try required(prim, USDSchema.nameAttribute))
        let domainProperty = try required(prim, USDSchema.graphDomainAttribute)
        guard let domain = GraphDomain(rawValue: try string(domainProperty)) else {
            throw .unsupported(line: domainProperty.line, "unknown graph domain")
        }
        let nextProperty = try required(prim, USDSchema.nextNodeIDAttribute)
        let nextNode = try integer(nextProperty.value ?? .word("None"), line: nextProperty.line)

        var nodes: [GraphNode] = []
        var connections: [GraphConnection] = []
        for child in prim.children {
            let id = try nodeID(child.name, line: child.line)
            let definition = try string(try required(child, USDSchema.definitionAttribute))
            let inputs = try ports(try required(child, USDSchema.inputsAttribute))
            let outputs = try ports(try required(child, USDSchema.outputsAttribute))
            var position = SIMD2<Float>.zero
            if let p = child.property(USDSchema.positionAttribute) {
                let v = try floats(p, count: 2)
                position = SIMD2(v[0], v[1])
            }
            var values: [String: GraphValue] = [:]
            for port in inputs {
                if let property = child.property(USDSchema.valuePrefix + port.name) {
                    values[port.name] = try graphValue(property, as: port.type)
                }
                if let property = child.property(USDSchema.linkPrefix + port.name) {
                    let text = try string(property)
                    guard let dot = text.firstIndex(of: "."), dot != text.startIndex else {
                        throw .syntax(line: property.line, "link '\(text)' is not n<id>.<output>")
                    }
                    let source = try nodeID(String(text[..<dot]), line: property.line)
                    connections.append(GraphConnection(
                        from: PortReference(source, String(text[text.index(after: dot)...])),
                        to: PortReference(id, port.name)
                    ))
                }
            }
            nodes.append(GraphNode(
                id: id, definition: definition, inputs: inputs, outputs: outputs, values: values, position: position
            ))
        }
        return GraphDocument(
            id: GraphID(rawValue: raw), name: name, domain: domain, nodes: nodes,
            connections: connections, nextNodeID: GraphNodeID(rawValue: nextNode)
        )
    }

    func nodeID(_ name: String, line: Int) throws(USDError) -> GraphNodeID {
        guard name.hasPrefix("n"), let raw = UInt64(name.dropFirst()), raw > 0 else {
            throw .syntax(line: line, "'\(name)' is not a graph node name n<id>")
        }
        return GraphNodeID(rawValue: raw)
    }

    func ports(_ property: USDAProperty) throws(USDError) -> [GraphPort] {
        guard case .list(let items)? = property.value else {
            throw .syntax(line: property.line, "\(property.name) must be a string array")
        }
        var result: [GraphPort] = []
        for item in items {
            guard case .string(let text) = item, let colon = text.firstIndex(of: ":"),
                  let type = PortType(String(text[text.index(after: colon)...]))
            else {
                throw .syntax(line: property.line, "\(property.name) entry is not name:type")
            }
            result.append(GraphPort(String(text[..<colon]), type))
        }
        return result
    }

    /// Reads a constant by the port's type, not the USD type name, so a
    /// reformatted file reads the same.
    func graphValue(_ property: USDAProperty, as type: PortType) throws(USDError) -> GraphValue {
        switch type {
        case .float: return .float(try float(property))
        case .vector2: let v = try floats(property, count: 2); return .vector2(SIMD2(v[0], v[1]))
        case .vector3: let v = try floats(property, count: 3); return .vector3(SIMD3(v[0], v[1], v[2]))
        case .vector4: let v = try floats(property, count: 4); return .vector4(SIMD4(v[0], v[1], v[2], v[3]))
        case .color: let v = try floats(property, count: 4); return .color(SIMD4(v[0], v[1], v[2], v[3]))
        case .boolean: return .boolean(try bool(property))
        case .string: return .string(try string(property))
        case .integer:
            guard case .number(let text)? = property.value, let v = Int64(text) else {
                throw .syntax(line: property.line, "\(property.name) must be an integer")
            }
            return .integer(v)
        case .entity:
            let raw = try integer(property.value ?? .word("None"), line: property.line)
            return .entity(raw == 0 ? nil : EntityID(rawValue: raw))
        case .transform:
            let v = try floatArray(property, count: 10)
            return .transform(Transform(
                position: SIMD3(v[0], v[1], v[2]),
                rotation: Rotation(x: v[4], y: v[5], z: v[6], w: v[3]),
                scale: SIMD3(v[7], v[8], v[9])
            ))
        case .material:
            let v = try floatArray(property, count: 6)
            return .material(Material(baseColor: SIMD4(v[0], v[1], v[2], v[3]), metallic: v[4], roughness: v[5]))
        case .texture, .mesh, .execution, .custom:
            throw .unsupported(line: property.line, "\(type) inputs carry no constants")
        }
    }

    func floatArray(_ property: USDAProperty, count: Int) throws(USDError) -> [Float] {
        guard case .list(let values)? = property.value, values.count == count else {
            throw .syntax(line: property.line, "\(property.name) must be a \(count)-element float array")
        }
        var result: [Float] = []
        for value in values {
            result.append(try float(value, line: property.line))
        }
        return result
    }

    /// Composition arcs and non-`def` specs would change what the stage
    /// means; Gama cannot keep them, so it refuses rather than drop them on
    /// the next save.
    func refuseComposition(_ prim: USDAPrim) throws(USDError) {
        guard prim.specifier == "def" else {
            throw .unsupported(line: prim.line, "'\(prim.specifier)' prim '\(prim.name)'")
        }
        for key in ["references", "payload", "inherits", "specializes", "variants", "variantSets", "instanceable"]
        where prim.metadata[key] != nil {
            throw .unsupported(line: prim.line, "\(key) on '\(prim.name)'")
        }
        for child in prim.children {
            try refuseComposition(child)
        }
    }

    mutating func collectMaterials(_ prim: USDAPrim, path: String) {
        let own = "\(path)/\(prim.name)"
        if prim.typeName == "Material" { materials[own] = prim }
        for child in prim.children {
            collectMaterials(child, path: own)
        }
    }

    // MARK: Entities

    mutating func entity(_ prim: USDAPrim, parent: EntityID?) throws(USDError) -> EntityID {
        guard let idProperty = prim.property(USDSchema.idAttribute), let idValue = idProperty.value else {
            throw .unsupported(line: prim.line, "prim '\(prim.name)' has no \(USDSchema.idAttribute)")
        }
        let raw = try integer(idValue, line: idProperty.line)
        guard raw > 0, raw < UInt64.max else {
            throw .syntax(line: idProperty.line, "\(USDSchema.idAttribute) must be in 1..<\(UInt64.max)")
        }
        let id = EntityID(rawValue: raw)
        if let first = seen[id] {
            throw .syntax(line: idProperty.line, "\(USDSchema.idAttribute) \(raw) already used on line \(first)")
        }
        seen[id] = idProperty.line

        var name = prim.name
        if let property = prim.property(USDSchema.nameAttribute) {
            name = try string(property)
        }

        var components: [ComponentKind: Component] = [:]
        try readOwnComponents(prim, into: &components)

        var children: [EntityID] = []
        for child in prim.children {
            if child.property(USDSchema.componentAttribute) != nil {
                try fold(child, into: &components)
            } else if child.typeName == "Scope", child.name == USDSchema.looksScope {
                continue
            } else {
                children.append(try entity(child, parent: id))
            }
        }
        records.append(EntityRecord(id: id, name: name, parent: parent, children: children, components: components))
        return id
    }

    /// Components stored on the entity prim itself.
    func readOwnComponents(_ prim: USDAPrim, into components: inout [ComponentKind: Component]) throws(USDError) {
        if let transform = try transform(prim) {
            components[.transform] = .transform(transform)
        }
        if let binding = prim.property("material:binding") {
            components[.material] = .material(try material(binding))
        }
        if let visible = prim.property(USDSchema.visibleAttribute) {
            var locked = false
            if let property = prim.property(USDSchema.lockedAttribute) { locked = try bool(property) }
            components[.visibility] = .visibility(Visibility(visible: try bool(visible), locked: locked))
        } else if case .string("invisible")? = prim.property("visibility")?.value {
            components[.visibility] = .visibility(Visibility(visible: false))
        }
        if let component = try typedComponent(prim, allowXform: true) {
            components[component.kind] = component
        }
    }

    /// A `gama:component` child prim, folded back into its entity.
    func fold(_ prim: USDAPrim, into components: inout [ComponentKind: Component]) throws(USDError) {
        guard let component = try typedComponent(prim, allowXform: false) else {
            throw .unsupported(line: prim.line, "component prim '\(prim.name)' has no component type")
        }
        guard components[component.kind] == nil else {
            throw .syntax(line: prim.line, "entity holds two \(component.kind.displayName) components")
        }
        components[component.kind] = component
    }

    /// The mesh, light, or camera a prim's type declares; `nil` for `Xform`.
    func typedComponent(_ prim: USDAPrim, allowXform: Bool) throws(USDError) -> Component? {
        let type = prim.typeName ?? ""
        if type == "Xform", allowXform { return nil }
        if let primitive = USDSchema.primitive(forTypeName: type) { return .mesh(primitive) }
        if USDSchema.lightTypeNames.contains(type) { return .light(try light(prim)) }
        if type == USDSchema.cameraTypeName { return .camera(try camera(prim)) }
        throw .unsupported(line: prim.line, "prim type '\(type.isEmpty ? "(none)" : type)' on '\(prim.name)'")
    }

    // MARK: Components

    func transform(_ prim: USDAPrim) throws(USDError) -> Transform? {
        let translate = prim.property("xformOp:translate")
        let orient = prim.property("xformOp:orient")
        let scale = prim.property("xformOp:scale")
        guard translate != nil || orient != nil || scale != nil else { return nil }
        var transform = Transform.identity
        if let translate {
            let v = try floats(translate, count: 3)
            transform.position = SIMD3(v[0], v[1], v[2])
        }
        if let orient {
            let q = try floats(orient, count: 4)
            transform.rotation = Rotation(x: q[1], y: q[2], z: q[3], w: q[0])
        }
        if let scale {
            let v = try floats(scale, count: 3)
            transform.scale = SIMD3(v[0], v[1], v[2])
        }
        return transform
    }

    func material(_ binding: USDAProperty) throws(USDError) -> Material {
        guard case .path(let path)? = binding.value else {
            throw .syntax(line: binding.line, "material:binding must target a path")
        }
        guard let material = materials[path] else {
            throw .syntax(line: binding.line, "material:binding targets <\(path)>, which is not a Material")
        }
        guard let shader = material.children.first(where: {
            $0.typeName == "Shader" && $0.property("info:id")?.value == .string("UsdPreviewSurface")
        }) else {
            throw .unsupported(line: material.line, "material <\(path)> has no UsdPreviewSurface shader")
        }
        // UsdPreviewSurface's own defaults for anything unauthored.
        var color: [Float] = [0.18, 0.18, 0.18]
        var opacity: Float = 1, metallic: Float = 0, roughness: Float = 0.5
        if let p = shader.property("inputs:diffuseColor") { color = try floats(p, count: 3) }
        if let p = shader.property("inputs:opacity") { opacity = try float(p) }
        if let p = shader.property("inputs:metallic") { metallic = try float(p) }
        if let p = shader.property("inputs:roughness") { roughness = try float(p) }
        return Material(baseColor: SIMD4(color[0], color[1], color[2], opacity), metallic: metallic, roughness: roughness)
    }

    func light(_ prim: USDAPrim) throws(USDError) -> Light {
        let intensity = try float(required(prim, USDSchema.intensityAttribute))
        var color = SIMD3<Float>(repeating: 1)
        if let p = prim.property("inputs:color") {
            let c = try floats(p, count: 3)
            color = SIMD3(c[0], c[1], c[2])
        }
        let kind: LightKind
        if prim.typeName == "DistantLight" {
            kind = .directional
        } else {
            let radius = try float(required(prim, USDSchema.attenuationRadiusAttribute))
            if let inner = prim.property(USDSchema.innerAngleAttribute) {
                kind = .spot(
                    innerAngleDegrees: try float(inner),
                    outerAngleDegrees: try float(required(prim, USDSchema.outerAngleAttribute)),
                    attenuationRadius: radius
                )
            } else {
                kind = .point(attenuationRadius: radius)
            }
        }
        return Light(kind: kind, color: color, intensity: intensity)
    }

    func camera(_ prim: USDAPrim) throws(USDError) -> CameraSettings {
        let fov = try float(required(prim, USDSchema.fieldOfViewAttribute))
        var near: Float = 0.01, far: Float = 1000
        if let p = prim.property("clippingRange") {
            let range = try floats(p, count: 2)
            near = range[0]
            far = range[1]
        }
        return CameraSettings(fieldOfViewDegrees: fov, near: near, far: far)
    }

    // MARK: Scalars

    func required(_ prim: USDAPrim, _ name: String) throws(USDError) -> USDAProperty {
        guard let property = prim.property(name) else {
            throw .unsupported(line: prim.line, "'\(prim.name)' has no \(name)")
        }
        return property
    }

    func float(_ property: USDAProperty) throws(USDError) -> Float {
        guard let value = property.value else { throw .syntax(line: property.line, "\(property.name) has no value") }
        return try float(value, line: property.line)
    }

    func float(_ value: USDAValue, line: Int) throws(USDError) -> Float {
        guard case .number(let text) = value, let result = Float(text) else {
            throw .syntax(line: line, "expected a number")
        }
        return result
    }

    func floats(_ property: USDAProperty, count: Int) throws(USDError) -> [Float] {
        guard case .tuple(let values)? = property.value, values.count == count else {
            throw .syntax(line: property.line, "\(property.name) must be a \(count)-tuple")
        }
        var result: [Float] = []
        for value in values {
            result.append(try float(value, line: property.line))
        }
        return result
    }

    func integer(_ value: USDAValue, line: Int) throws(USDError) -> UInt64 {
        guard case .number(let text) = value, let result = UInt64(text) else {
            throw .syntax(line: line, "expected a non-negative integer")
        }
        return result
    }

    func bool(_ property: USDAProperty) throws(USDError) -> Bool {
        switch property.value {
        case .number("1")?, .word("true")?: return true
        case .number("0")?, .word("false")?: return false
        default: throw .syntax(line: property.line, "\(property.name) must be 0 or 1")
        }
    }

    func string(_ property: USDAProperty) throws(USDError) -> String {
        guard case .string(let text)? = property.value else {
            throw .syntax(line: property.line, "\(property.name) must be a string")
        }
        return text
    }
}

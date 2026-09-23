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
        guard found == UInt64(USDSchema.formatVersion) else {
            throw .unsupported(line: 1, "\(USDSchema.formatVersionKey) \(found) is not supported by this reader")
        }

        for prim in layer.prims {
            collectMaterials(prim, path: "")
        }
        var roots: [EntityID] = []
        for prim in layer.prims where prim.specifier == "def" {
            roots.append(try entity(prim, parent: nil))
        }

        let next: EntityID
        if let value = data[USDSchema.nextEntityIDKey] {
            next = EntityID(rawValue: try integer(value, line: 1))
        } else {
            next = EntityID(rawValue: (records.map(\.id.rawValue).max() ?? 0) + 1)
        }
        do {
            return try SceneDocument(restoring: records, roots: roots, nextEntityID: next)
        } catch {
            throw .invalid(error)
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
        guard raw > 0 else { throw .syntax(line: idProperty.line, "\(USDSchema.idAttribute) must be positive") }
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
        for child in prim.children where child.specifier == "def" {
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

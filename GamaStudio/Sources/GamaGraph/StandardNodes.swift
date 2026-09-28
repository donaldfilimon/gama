import GamaAuthoring

extension NodeRegistry {
    /// The built-in node set (ADR 0007): constants, float math, vectors,
    /// colors, and two outputs that write to the scene: a material output
    /// (material graphs) and a transform output (scene, logic, and animation
    /// graphs).
    public static let standard = NodeRegistry(StandardNodes.all)
}

enum StandardNodes {
    static let all: [NodeDefinition] = constants + math + vectors + colors + outputs

    // MARK: Constants

    static let constants: [NodeDefinition] = [
        NodeDefinition(
            id: "constant.float", title: "Float", category: "Constant",
            inputs: [GraphPort("value", .float)], outputs: [GraphPort("value", .float)],
            defaults: ["value": .float(0)],
            compute: { inputs throws(GraphError) in ["value": .float(try inputs.float("value"))] }
        ),
        NodeDefinition(
            id: "constant.vector3", title: "Vector3", category: "Constant",
            inputs: [GraphPort("value", .vector3)], outputs: [GraphPort("value", .vector3)],
            defaults: ["value": .vector3(.zero)],
            compute: { inputs throws(GraphError) in ["value": .vector3(try inputs.vector3("value"))] }
        ),
        NodeDefinition(
            id: "constant.color", title: "Color", category: "Constant",
            inputs: [GraphPort("value", .color)], outputs: [GraphPort("value", .color)],
            defaults: ["value": .color(SIMD4(0.8, 0.8, 0.8, 1))],
            compute: { inputs throws(GraphError) in ["value": .color(try inputs.color("value"))] }
        ),
    ]

    // MARK: Float math

    static func binary(
        _ id: String, _ title: String, _ op: @escaping @Sendable (Float, Float) throws(GraphError) -> Float,
        b: Float
    ) -> NodeDefinition {
        NodeDefinition(
            id: id, title: title, category: "Math",
            inputs: [GraphPort("a", .float), GraphPort("b", .float)],
            outputs: [GraphPort("result", .float)],
            defaults: ["a": .float(0), "b": .float(b)],
            compute: { inputs throws(GraphError) in
                ["result": .float(try op(try inputs.float("a"), try inputs.float("b")))]
            }
        )
    }

    static let math: [NodeDefinition] = [
        binary("math.add", "Add", { $0 + $1 }, b: 0),
        binary("math.subtract", "Subtract", { $0 - $1 }, b: 0),
        binary("math.multiply", "Multiply", { $0 * $1 }, b: 1),
        NodeDefinition(
            id: "math.divide", title: "Divide", category: "Math",
            inputs: [GraphPort("a", .float), GraphPort("b", .float)],
            outputs: [GraphPort("result", .float)],
            defaults: ["a": .float(0), "b": .float(1)],
            compute: { inputs throws(GraphError) in
                let b = try inputs.float("b")
                guard b != 0 else { throw inputs.fail("division by zero") }
                return ["result": .float(try inputs.float("a") / b)]
            }
        ),
        NodeDefinition(
            id: "math.clamp", title: "Clamp", category: "Math",
            inputs: [GraphPort("value", .float), GraphPort("min", .float), GraphPort("max", .float)],
            outputs: [GraphPort("result", .float)],
            defaults: ["value": .float(0), "min": .float(0), "max": .float(1)],
            compute: { inputs throws(GraphError) in
                let low = try inputs.float("min"), high = try inputs.float("max")
                guard low <= high else { throw inputs.fail("min is greater than max") }
                return ["result": .float(Swift.min(Swift.max(try inputs.float("value"), low), high))]
            }
        ),
        NodeDefinition(
            id: "math.mix", title: "Mix", category: "Math",
            inputs: [GraphPort("a", .float), GraphPort("b", .float), GraphPort("t", .float)],
            outputs: [GraphPort("result", .float)],
            defaults: ["a": .float(0), "b": .float(1), "t": .float(0.5)],
            compute: { inputs throws(GraphError) in
                let a = try inputs.float("a"), b = try inputs.float("b"), t = try inputs.float("t")
                return ["result": .float(a + (b - a) * t)]
            }
        ),
    ]

    // MARK: Vectors

    static let vectors: [NodeDefinition] = [
        NodeDefinition(
            id: "vector3.compose", title: "Compose Vector3", category: "Vector",
            inputs: [GraphPort("x", .float), GraphPort("y", .float), GraphPort("z", .float)],
            outputs: [GraphPort("vector", .vector3)],
            defaults: ["x": .float(0), "y": .float(0), "z": .float(0)],
            compute: { inputs throws(GraphError) in
                ["vector": .vector3(SIMD3(try inputs.float("x"), try inputs.float("y"), try inputs.float("z")))]
            }
        ),
        NodeDefinition(
            id: "vector3.split", title: "Split Vector3", category: "Vector",
            inputs: [GraphPort("vector", .vector3)],
            outputs: [GraphPort("x", .float), GraphPort("y", .float), GraphPort("z", .float)],
            defaults: ["vector": .vector3(.zero)],
            compute: { inputs throws(GraphError) in
                let v = try inputs.vector3("vector")
                return ["x": .float(v.x), "y": .float(v.y), "z": .float(v.z)]
            }
        ),
        NodeDefinition(
            id: "vector3.add", title: "Add Vector3", category: "Vector",
            inputs: [GraphPort("a", .vector3), GraphPort("b", .vector3)],
            outputs: [GraphPort("result", .vector3)],
            defaults: ["a": .vector3(.zero), "b": .vector3(.zero)],
            compute: { inputs throws(GraphError) in
                ["result": .vector3(try inputs.vector3("a") + inputs.vector3("b"))]
            }
        ),
        NodeDefinition(
            id: "vector3.scale", title: "Scale Vector3", category: "Vector",
            inputs: [GraphPort("vector", .vector3), GraphPort("factor", .float)],
            outputs: [GraphPort("result", .vector3)],
            defaults: ["vector": .vector3(.zero), "factor": .float(1)],
            compute: { inputs throws(GraphError) in
                ["result": .vector3(try inputs.vector3("vector") * inputs.float("factor"))]
            }
        ),
    ]

    // MARK: Colors

    static let colors: [NodeDefinition] = [
        NodeDefinition(
            id: "color.compose", title: "Compose Color", category: "Color",
            inputs: [GraphPort("r", .float), GraphPort("g", .float), GraphPort("b", .float), GraphPort("a", .float)],
            outputs: [GraphPort("color", .color)],
            defaults: ["r": .float(0.8), "g": .float(0.8), "b": .float(0.8), "a": .float(1)],
            compute: { inputs throws(GraphError) in
                ["color": .color(SIMD4(
                    try inputs.float("r"), try inputs.float("g"), try inputs.float("b"), try inputs.float("a")
                ))]
            }
        ),
        NodeDefinition(
            id: "color.mix", title: "Mix Color", category: "Color",
            inputs: [GraphPort("a", .color), GraphPort("b", .color), GraphPort("t", .float)],
            outputs: [GraphPort("color", .color)],
            defaults: ["a": .color(SIMD4(0, 0, 0, 1)), "b": .color(SIMD4(1, 1, 1, 1)), "t": .float(0.5)],
            compute: { inputs throws(GraphError) in
                let a = try inputs.color("a"), b = try inputs.color("b"), t = try inputs.float("t")
                return ["color": .color(a + (b - a) * t)]
            }
        ),
        NodeDefinition(
            id: "color.multiply", title: "Multiply Color", category: "Color",
            inputs: [GraphPort("color", .color), GraphPort("factor", .float)],
            outputs: [GraphPort("color", .color)],
            defaults: ["color": .color(SIMD4(1, 1, 1, 1)), "factor": .float(1)],
            compute: { inputs throws(GraphError) in
                let c = try inputs.color("color"), f = try inputs.float("factor")
                return ["color": .color(SIMD4(c.x * f, c.y * f, c.z * f, c.w))]
            }
        ),
    ]

    // MARK: Outputs

    static let outputs: [NodeDefinition] = [
        NodeDefinition(
            id: "output.material", title: "Material Output", category: "Output", domains: [.material],
            inputs: [
                GraphPort("target", .entity), GraphPort("base_color", .color),
                GraphPort("metallic", .float), GraphPort("roughness", .float),
            ],
            outputs: [],
            defaults: [
                "target": .entity(nil), "base_color": .color(SIMD4(0.8, 0.8, 0.8, 1)),
                "metallic": .float(0), "roughness": .float(0.5),
            ],
            emit: { inputs, document throws(GraphError) in
                // No target, or one since deleted: the output is inert.
                guard let target = try inputs.entity("target"), document.contains(target) else { return [] }
                // Channels saturate to 0…1, as a PBR material output does,
                // so upstream math cannot produce an invalid material.
                func saturate(_ v: Float) -> Float { Swift.min(Swift.max(v, 0), 1) }
                let c = try inputs.color("base_color")
                let material = Material(
                    baseColor: SIMD4(saturate(c.x), saturate(c.y), saturate(c.z), saturate(c.w)),
                    metallic: saturate(try inputs.float("metallic")),
                    roughness: saturate(try inputs.float("roughness"))
                )
                return [SetComponent(target, .material(material))]
            }
        ),
        NodeDefinition(
            id: "output.transform", title: "Transform Output", category: "Output",
            domains: [.scene, .logic, .animation],
            inputs: [GraphPort("target", .entity), GraphPort("position", .vector3), GraphPort("scale", .vector3)],
            outputs: [],
            defaults: ["target": .entity(nil), "position": .vector3(.zero), "scale": .vector3(SIMD3(repeating: 1))],
            emit: { inputs, document throws(GraphError) in
                guard let target = try inputs.entity("target"), document.contains(target) else { return [] }
                // Rotation is kept: the output owns position and scale only.
                var transform = Transform.identity
                if case .transform(let current)? = document.component(.transform, of: target) {
                    transform = current
                }
                transform.position = try inputs.vector3("position")
                transform.scale = try inputs.vector3("scale")
                return [SetComponent(target, .transform(transform))]
            }
        ),
    ]
}

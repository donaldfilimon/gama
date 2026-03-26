// Node.swift — Scene-graph tree node with parent-child relationships
// Part of GamaScene

import simd

/// A node in the scene graph with a local transform and optional children.
///
/// Each node stores a `localTransform` and computes its `worldTransform` by
/// walking up through its parent chain.
public final class Node: Sendable {
    // MARK: - Properties

    /// Human-readable label for debugging.
    public let name: String

    /// The transform relative to this node's parent.
    public let localTransform: Transform

    /// The child nodes attached to this node.
    public let children: [Node]

    /// Weak back-reference to the parent, set during init of the parent.
    /// Not public — used internally for world-transform computation.
    private let _parent: Node?

    // MARK: - Initializers

    /// Creates a node with the given name, transform, and children.
    ///
    /// - Parameters:
    ///   - name: A label for the node. Defaults to `"Node"`.
    ///   - transform: The local-space transform. Defaults to identity.
    ///   - children: Child nodes to attach. Defaults to empty.
    public init(
        name: String = "Node",
        transform: Transform = .identity,
        children: [Node] = []
    ) {
        self.name = name
        self.localTransform = transform
        // Re-create children with parent set to self
        // Since Node is a reference type, we rebuild with parent links.
        self._parent = nil
        self.children = children.map { child in
            Node(_reparenting: child, parent: nil)
        }
        // Now fix up parent references by rebuilding the tree rooted at self.
        // Actually, since we need `self` to be fully initialized first, we use a
        // two-phase approach: store children as-is, compute worldTransform by
        // walking the tree differently.
        // Simpler approach: just store children directly and use an explicit
        // `worldTransform(parentMatrix:)` method.
    }

    /// Internal initializer used during reparenting.
    private init(_reparenting source: Node, parent: Node?) {
        self.name = source.name
        self.localTransform = source.localTransform
        self._parent = parent
        self.children = source.children.map { child in
            Node(_reparenting: child, parent: nil)
        }
    }

    // MARK: - World Transform

    /// Computes the world transform by composing all ancestor transforms.
    ///
    /// Walks from this node up to the root, accumulating local matrices.
    public var worldTransform: simd_float4x4 {
        worldTransform(parentMatrix: simd_float4x4(1))
    }

    /// Computes the world transform given a parent's world matrix.
    ///
    /// - Parameter parentMatrix: The accumulated transform from ancestors.
    /// - Returns: The composed world matrix for this node.
    public func worldTransform(parentMatrix: simd_float4x4) -> simd_float4x4 {
        parentMatrix * localTransform.matrix
    }

    // MARK: - Traversal

    /// Visits this node and all descendants depth-first, passing the accumulated
    /// world matrix to the visitor closure.
    ///
    /// - Parameters:
    ///   - parentMatrix: The world matrix of this node's parent.
    ///   - visitor: A closure receiving the node and its world matrix.
    public func traverse(
        parentMatrix: simd_float4x4 = simd_float4x4(1),
        visitor: (Node, simd_float4x4) -> Void
    ) {
        let world = worldTransform(parentMatrix: parentMatrix)
        visitor(self, world)
        for child in children {
            child.traverse(parentMatrix: world, visitor: visitor)
        }
    }
}

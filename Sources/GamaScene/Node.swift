// Node.swift — Scene-graph tree node with parent-child relationships
// Part of GamaScene

import simd

/// A node in the scene graph with a local transform and optional children.
///
/// Each node stores a `localTransform` and computes its `worldTransform`
/// by composing the parent's world matrix via ``traverse(parentMatrix:visitor:)``.
public final class Node: Sendable {
    // MARK: - Properties

    /// Human-readable label for debugging.
    public let name: String

    /// The transform relative to this node's parent.
    public let localTransform: Transform

    /// The child nodes attached to this node.
    public let children: [Node]

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
        self.children = children
    }

    // MARK: - World Transform

    /// Computes the world transform assuming this node is a root (no parent).
    ///
    /// For nodes within a hierarchy, use ``traverse(parentMatrix:visitor:)``
    /// to propagate parent matrices down the tree.
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

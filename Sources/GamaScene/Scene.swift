// Scene.swift — Root container for a renderable 3D scene
// Part of GamaScene

import GamaCore
import GamaMath

/// A complete scene containing a node hierarchy, camera, and background color.
///
/// `Scene` serves as the top-level container passed to a renderer.
public struct Scene: Sendable {
    // MARK: - Properties

    /// The root of the node hierarchy.
    public var rootNode: Node

    /// The active camera used for rendering.
    public var camera: SceneCamera

    /// The clear color used as the scene background.
    public var backgroundColor: ClearColor

    // MARK: - Initializers

    /// Creates a scene with the given root node, camera, and background.
    ///
    /// - Parameters:
    ///   - rootNode: The root node of the scene graph.
    ///   - camera: The camera to render from.
    ///   - backgroundColor: The background clear color. Defaults to black.
    public init(
        rootNode: Node = Node(name: "Root"),
        camera: SceneCamera = SceneCamera(),
        backgroundColor: ClearColor = ClearColor(r: 0, g: 0, b: 0, a: 1)
    ) {
        self.rootNode = rootNode
        self.camera = camera
        self.backgroundColor = backgroundColor
    }
}

//  ViewportController.swift — GamaStudioEditor
//
//  The RealityKit half of the editor: an `ARView` showing `StudioModel`'s
//  bridge, lit and framed by a fixed camera, that turns a click into a
//  selection. The host (`GamaHostView`) owns placement; this file owns only
//  what is drawn inside the viewport and what a click in it means.
//
//  Edits need no extra plumbing here. `StudioModel` applies every change to
//  `bridge` synchronously, and `bridge.root` is parented under this view's
//  anchor, so RealityKit renders the edited entity tree on its next frame.

#if canImport(AppKit) && canImport(RealityKit)

public import AppKit
public import GamaAuthoring
public import GamaReality
public import RealityKit

/// Owns the RealityKit viewport for a ``StudioModel``: the `ARView`, the
/// scene anchor holding the model's projected entities, a camera and a light,
/// and click-to-select picking.
///
/// The controller does not place ``arView`` anywhere; attach it to
/// ``StudioApp/viewportRegion`` on a `GamaHostView`, which sizes and shows it
/// each frame.
@MainActor
public final class ViewportController: NSObject {
    /// The RealityKit view to attach to the host's viewport region.
    public let arView: ARView

    /// The model whose bridge this view shows and whose selection clicks set.
    public let model: StudioModel

    /// Called after every click has updated the selection (including a click
    /// on empty space that cleared it), so the host can redraw its panels.
    private let onSelectionChange: @MainActor () -> Void

    /// Creates the viewport over `model`'s bridge and installs click picking.
    ///
    /// - Parameters:
    ///   - model: The editing model to show and select in.
    ///   - onSelectionChange: Called after each click-driven selection
    ///     change; a host typically calls `invalidate()` here.
    public init(model: StudioModel, onSelectionChange: @escaping @MainActor () -> Void) {
        self.model = model
        self.onSelectionChange = onSelectionChange
        arView = ARView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        super.init()

        arView.environment.background = .color(NSColor(white: 0.12, alpha: 1))

        let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        anchor.addChild(model.bridge.root)

        // Frames the sample scene (ground plus three primitives along X) from
        // above and in front.
        let camera = PerspectiveCamera()
        camera.look(at: SIMD3<Float>(0, 0, 0), from: SIMD3<Float>(0, 3, 7), relativeTo: nil)
        anchor.addChild(camera)

        // Angled down and across the scene so every primitive shows shading.
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: SIMD3<Float>(0, 0, 0), from: SIMD3<Float>(3, 6, 4), relativeTo: nil)
        anchor.addChild(light)

        arView.scene.addAnchor(anchor)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        arView.addGestureRecognizer(click)
    }

    /// The authored identity a hit on `entity` selects: the nearest of
    /// `entity` and its ancestors that `bridge` projected, or `nil` for no
    /// hit and for entities outside the projection (the camera, the light,
    /// the anchor, `bridge.root`). Walking up means a hit on an unprojected
    /// sub-part still selects the entity that owns it.
    public static func pickedEntityID(for entity: Entity?, in bridge: RealityBridge) -> EntityID? {
        var current = entity
        while let candidate = current {
            if let id = bridge.id(for: candidate) { return id }
            current = candidate.parent
        }
        return nil
    }

    /// Selects the entity under `point` (in ``arView``'s coordinates), or
    /// clears the selection when nothing projected is there, then reports
    /// the change.
    public func pick(at point: CGPoint) {
        let hit = arView.entity(at: point)
        model.select(Self.pickedEntityID(for: hit, in: model.bridge))
        onSelectionChange()
    }

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        pick(at: recognizer.location(in: arView))
    }
}

#endif

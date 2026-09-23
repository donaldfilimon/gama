//  ViewportController.swift — GamaStudioEditor
//
//  The RealityKit half of the editor: an `ARView` showing `StudioModel`'s
//  bridge, lit by a fixed light and viewed through an orbit camera (drag,
//  scroll, and pinch, chosen by device), that turns a click into a
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
/// scene anchor holding the model's projected entities, an orbit camera and a
/// light, and click-to-select picking.
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
        arView = StudioViewportView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        super.init()

        arView.environment.background = .color(NSColor(white: 0.12, alpha: 1))

        let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        anchor.addChild(model.bridge.root)

        // Frames the sample scene (ground plus three primitives along X) from
        // above and in front; the orbit controls move it from there.
        anchor.addChild(camera)
        applyCamera()

        // Angled down and across the scene so every primitive shows shading.
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: SIMD3<Float>(0, 0, 0), from: SIMD3<Float>(3, 6, 4), relativeTo: nil)
        anchor.addChild(light)

        arView.scene.addAnchor(anchor)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        arView.addGestureRecognizer(click)

        // Left-drag orbits (Option+left-drag pans); right-drag pans. A drag
        // makes the click recognizer fail, so dragging never changes the
        // selection, and a click without movement still picks.
        let leftDrag = NSPanGestureRecognizer(target: self, action: #selector(handleLeftDrag(_:)))
        leftDrag.buttonMask = 0x1
        arView.addGestureRecognizer(leftDrag)
        let rightDrag = NSPanGestureRecognizer(target: self, action: #selector(handleRightDrag(_:)))
        rightDrag.buttonMask = 0x2
        arView.addGestureRecognizer(rightDrag)

        // Scroll and pinch arrive as view events, not gestures.
        if let view = arView as? StudioViewportView {
            view.onScroll = { [weak self] event in self?.scroll(with: event) }
            view.onMagnify = { [weak self] magnification in self?.magnify(by: magnification) }
        }
    }

    // MARK: Camera

    /// The current orbit camera. Editor state only: not a document command,
    /// so it is neither undoable nor saved (ADR 0003).
    public private(set) var orbit = OrbitCamera(lookingAt: .zero, from: SIMD3<Float>(0, 3, 7))

    /// The RealityKit camera ``orbit`` drives.
    public let camera = PerspectiveCamera()

    /// Radians of orbit per point of drag or precise scroll.
    public static let orbitPerPoint: Float = 0.008
    /// Fraction of the eye distance panned per point of drag or precise scroll.
    public static let panPerPointPerMeter: Float = 0.0015
    /// Zoom factor per line of a notched mouse wheel.
    public static let zoomPerWheelLine: Float = 1.1

    /// Orbits by a drag of `dx`, `dy` points (AppKit coordinates, y up):
    /// dragging right turns the scene right, dragging up tilts the eye down.
    public func orbit(byDragX dx: CGFloat, dragY dy: CGFloat) {
        orbit.orbit(yawBy: -Float(dx) * Self.orbitPerPoint, pitchBy: -Float(dy) * Self.orbitPerPoint)
        applyCamera()
    }

    /// Pans by a drag of `dx`, `dy` points so the scene follows the pointer.
    public func pan(byDragX dx: CGFloat, dragY dy: CGFloat) {
        let metersPerPoint = orbit.distance * Self.panPerPointPerMeter
        orbit.pan(right: -Float(dx) * metersPerPoint, up: -Float(dy) * metersPerPoint)
        applyCamera()
    }

    /// Zooms by `scale` (below 1 moves closer).
    public func zoom(scale: Float) {
        orbit.zoom(scale: scale)
        applyCamera()
    }

    /// Routes a scroll event by device: a trackpad (precise, continuous
    /// deltas) orbits, or pans with Shift; a notched mouse wheel zooms.
    public func scroll(with event: NSEvent) {
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            if event.modifierFlags.contains(.shift) {
                pan(byDragX: dx, dragY: -dy)
            } else {
                orbit(byDragX: dx, dragY: -dy)
            }
        } else if dy != 0 {
            // Wheel up (positive delta) moves closer.
            zoom(scale: pow(Self.zoomPerWheelLine, -Float(dy)))
        }
    }

    /// Zooms by a trackpad pinch: spreading (positive magnification) moves closer.
    public func magnify(by magnification: CGFloat) {
        let factor = 1 + Float(magnification)
        guard factor > 0.05 else { return }
        zoom(scale: 1 / factor)
    }

    private func applyCamera() {
        camera.look(at: orbit.target, from: orbit.position, relativeTo: nil)
    }

    /// Aims the camera at the primary selection, or at the whole scene when
    /// nothing is selected, keeping the current viewing direction.
    ///
    /// Hidden entities still frame (finding a hidden object is useful). An
    /// entity with no visual bounds, such as one without a mesh, frames at
    /// its world position with ``OrbitCamera/frameMinimumRadius``.
    public func frameSelection() {
        let subject = model.session.selection.primary.flatMap { model.bridge.entity(for: $0) } ?? model.bridge.root
        let bounds = subject.visualBounds(recursive: true, relativeTo: nil, excludeInactive: false)
        let center: SIMD3<Float>
        let radius: Float
        if bounds.isEmpty {
            center = subject.position(relativeTo: nil)
            radius = OrbitCamera.frameMinimumRadius
        } else {
            center = bounds.center
            radius = (bounds.extents * bounds.extents).sum().squareRoot() / 2
        }
        orbit.frame(center: center, radius: radius, fieldOfViewDegrees: camera.camera.fieldOfViewInDegrees)
        applyCamera()
    }

    @objc private func handleLeftDrag(_ recognizer: NSPanGestureRecognizer) {
        let t = recognizer.translation(in: arView)
        recognizer.setTranslation(.zero, in: arView)
        if NSEvent.modifierFlags.contains(.option) {
            pan(byDragX: t.x, dragY: t.y)
        } else {
            orbit(byDragX: t.x, dragY: t.y)
        }
    }

    @objc private func handleRightDrag(_ recognizer: NSPanGestureRecognizer) {
        let t = recognizer.translation(in: arView)
        recognizer.setTranslation(.zero, in: arView)
        pan(byDragX: t.x, dragY: t.y)
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

/// The ARView subclass the controller shows.
///
/// Keyboard focus note (measured, see ViewportTests): a click makes this view
/// first responder, as AppKit does for any view that accepts it, but keys
/// still reach Gama because `ARView.keyDown` forwards what it does not use
/// to its next responder, the `GamaHostView`. The orbit controls use only the
/// mouse, trackpad scroll, and pinch — never keys — so Tab, arrows, and Enter
/// keep driving the panels.
final class StudioViewportView: ARView {
    /// Receives scroll events for the camera (set by the controller).
    var onScroll: (@MainActor (NSEvent) -> Void)?
    /// Receives pinch magnification for the camera (set by the controller).
    var onMagnify: (@MainActor (CGFloat) -> Void)?

    /// A click in a background window's viewport picks immediately instead
    /// of only activating the window, as a canvas does in most editors. It
    /// also lets a click delivered to an inactive process (a test runner)
    /// reach the gesture recognizer at all.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard let onScroll else { return super.scrollWheel(with: event) }
        onScroll(event)
    }

    override func magnify(with event: NSEvent) {
        guard let onMagnify else { return super.magnify(with: event) }
        onMagnify(event.magnification)
    }
}

#endif

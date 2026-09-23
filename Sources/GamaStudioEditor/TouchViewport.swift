//  TouchViewport.swift — GamaStudioEditor
//
//  The RealityKit viewport on iOS and visionOS (ADR 0008). ARView does not
//  exist on visionOS, so both platforms use a SwiftUI RealityView, wrapped in
//  a UIHostingController whose view fills gama's native viewport region.
//
//  iOS drives a virtual PerspectiveCamera with the same OrbitCamera math as
//  the macOS viewport: drag orbits, pinch zooms, tap selects. visionOS places
//  the window's 3D content in space, where RealityView has no camera, so the
//  stage itself turns and scales instead: drag turns it, pinch scales it, tap
//  selects, and Frame refits it around the selection.

#if canImport(UIKit) && canImport(RealityKit) && canImport(SwiftUI)

public import UIKit
public import SwiftUI
public import RealityKit
public import GamaAuthoring
public import GamaReality

/// Owns the touch viewport's editor state: the stage, camera or stage pose,
/// fallback light, and selection highlight. Like the macOS
/// ``ViewportController`` it never edits the document; taps go through
/// ``StudioModel/select(_:)``.
@MainActor
public final class TouchViewportController {
    public let model: StudioModel

    /// Everything the viewport shows: the bridge's projection, the selection
    /// highlight, the fallback light, and (on iOS) the camera.
    public let stage = Entity()
    public let selectionHighlight = SelectionHighlight()
    /// Lit only while the document has no enabled light (ADR 0004).
    public let editorLight = DirectionalLight()

    /// The orbit camera's pose (iOS) or, on visionOS, the direction the stage
    /// is turned to. Editor state (ADR 0003).
    public private(set) var orbit = OrbitCamera(lookingAt: .zero, from: SIMD3(0, 3, 7))

    #if os(visionOS)
    /// The stage's scale, fitted so the framed subject spans
    /// ``fittedSize`` meters in the window.
    public private(set) var stageScale: Float = 0.04
    /// Where the framed subject's center is, in document units.
    public private(set) var stageCenter = SIMD3<Float>.zero
    /// The size, in meters, Frame fits the subject to.
    public static let fittedSize: Float = 0.42
    #else
    /// The camera the RealityView's virtual camera looks through.
    public let camera = PerspectiveCamera()
    #endif

    /// Drag distance to orbit angle and pinch ratio to zoom, matching the
    /// macOS viewport's mouse feel.
    public static let orbitPerPoint: Float = 0.008

    private let onSelectionChange: @MainActor () -> Void

    /// The SwiftUI host. The app adds it as a child view controller before
    /// its ``view`` is attached to gama's viewport region.
    public private(set) lazy var hostingController: UIViewController = {
        let controller = UIHostingController(rootView: TouchViewportView(controller: self))
        controller.view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        return controller
    }()

    /// The view gama's native region shows.
    public var view: UIView { hostingController.view }

    public init(model: StudioModel, onSelectionChange: @escaping @MainActor () -> Void) {
        self.model = model
        self.onSelectionChange = onSelectionChange

        stage.name = "GamaStudio.stage"
        stage.addChild(model.bridge.root)
        stage.addChild(selectionHighlight.root)
        // SwiftUI entity gestures need an input target; on the root it covers
        // every projected entity, which already carries collision for picking.
        model.bridge.root.components.set(InputTargetComponent())

        editorLight.light.intensity = 3000
        editorLight.look(at: .zero, from: SIMD3(3, 6, 4), relativeTo: stage)
        stage.addChild(editorLight)

        #if os(visionOS)
        fit()  // setup, not a user's Frame: no console note
        #else
        stage.addChild(camera)
        applyCamera()
        #endif

        let previousDocumentListener = model.onDocumentChange
        model.onDocumentChange = { [weak self] in
            previousDocumentListener?()
            self?.refresh()
        }
        let previousSelectionListener = model.onSelectionChange
        model.onSelectionChange = { [weak self] in
            previousSelectionListener?()
            self?.refreshHighlight()
        }
        refresh()
    }

    // MARK: Refresh

    private func refresh() {
        editorLight.isEnabled = !ViewportSupport.documentHasEnabledLight(model.session.document)
        // A rebuilt projection (File > Open) is a new set of entities under
        // the same root, so the input target on the root still covers them.
        refreshHighlight()
    }

    private func refreshHighlight() {
        selectionHighlight.update(selection: model.session.selection.ordered, bridge: model.bridge, relativeTo: stage)
    }

    // MARK: Picking

    #if !os(visionOS)
    /// Selects what a tap at `point` hits (iOS), casting the ray itself so it
    /// can skip shapes the eye is inside: the sample Camera's marker sits at
    /// the orbit eye, and a hit on it at distance 0 would swallow every tap.
    /// The nearest hit in front of the eye wins, as on macOS; no hit clears
    /// the selection.
    public func pick(at point: CGPoint, in size: CGSize) {
        let (origin, direction) = orbit.ray(
            through: SIMD2(Float(point.x), Float(point.y)),
            in: SIMD2(Float(size.width), Float(size.height)),
            fieldOfViewDegrees: camera.camera.fieldOfViewInDegrees
        )
        let hits = stage.scene?.raycast(
            origin: origin, direction: direction, length: 1000, query: .all, mask: .all, relativeTo: stage
        ) ?? []
        let hit = hits.filter { $0.distance > Self.insideHitDistance }.min { $0.distance < $1.distance }
        pick(hit?.entity)
    }

    /// Hits at or below this distance start inside the shape and are skipped.
    static let insideHitDistance: Float = 1e-4
    #endif

    /// Selects what a tap hit, or clears the selection for an entity outside
    /// the projection, then reports the change.
    public func pick(_ entity: Entity?) {
        model.select(ViewportSupport.pickedEntityID(for: entity, in: model.bridge))
        ViewportSupport.notePick(in: model)
        onSelectionChange()
    }

    // MARK: Camera

    /// Turns the view by a drag, in points.
    public func orbit(byDragX dx: CGFloat, dragY dy: CGFloat) {
        orbit.orbit(yawBy: -Float(dx) * Self.orbitPerPoint, pitchBy: Float(dy) * Self.orbitPerPoint)
        applyCamera()
        ViewportSupport.noteCameraMove(in: model)
    }

    /// Zooms by a pinch ratio relative to the previous update: spreading
    /// (ratio above 1) moves closer on iOS and enlarges the stage on visionOS.
    public func pinch(by ratio: CGFloat) {
        guard ratio.isFinite, ratio > 0.05 else { return }
        #if os(visionOS)
        stageScale = min(max(stageScale * Float(ratio), 0.001), 10)
        #else
        orbit.zoom(scale: 1 / Float(ratio))
        #endif
        applyCamera()
        ViewportSupport.noteCameraMove(in: model)
    }

    /// Frames the primary selection, or the whole scene when nothing is
    /// selected. iOS moves the camera; visionOS recenters and rescales the
    /// stage so the subject spans ``fittedSize``.
    public func frameSelection() {
        fit()
        ViewportSupport.noteFrame(in: model)
    }

    /// Frames without a console note, for setup.
    private func fit() {
        let subject = model.session.selection.primary.flatMap { model.bridge.entity(for: $0) } ?? model.bridge.root
        let bounds = subject.visualBounds(recursive: true, relativeTo: stage, excludeInactive: false)
        let center: SIMD3<Float>
        let radius: Float
        if bounds.isEmpty {
            center = subject.position(relativeTo: stage)
            radius = OrbitCamera.frameMinimumRadius
        } else {
            center = bounds.center
            radius = max((bounds.extents * bounds.extents).sum().squareRoot() / 2, OrbitCamera.frameMinimumRadius)
        }
        #if os(visionOS)
        stageCenter = center
        stageScale = Self.fittedSize / (2 * radius)
        #else
        orbit.frame(center: center, radius: radius, fieldOfViewDegrees: camera.camera.fieldOfViewInDegrees)
        #endif
        applyCamera()
    }

    /// Looks through an authored camera (iOS). visionOS has no viewport
    /// camera to move, so it frames the camera's entity instead.
    public func lookThrough(_ id: EntityID) {
        #if os(visionOS)
        model.select(id)
        frameSelection()
        #else
        guard case .camera(let settings)? = model.session.document.component(.camera, of: id),
              let entity = model.bridge.entity(for: id)
        else { return }
        let eye = entity.position(relativeTo: stage)
        let direction = entity.convert(direction: SIMD3<Float>(0, 0, -1), to: stage)
        let length = (direction * direction).sum().squareRoot()
        guard length.isFinite, length > 0 else { return }
        orbit = OrbitCamera(lookingAt: eye + direction / length * orbit.distance, from: eye)
        camera.camera.fieldOfViewInDegrees = settings.fieldOfViewDegrees
        applyCamera()
        ViewportSupport.noteLookThrough(id, in: model)
        #endif
    }

    private func applyCamera() {
        #if os(visionOS)
        // Turn the stage the opposite way the orbit eye moved, so a drag
        // spins the scene under the finger, and tilt it toward the viewer by
        // the orbit pitch, as the iOS camera looks down on it; then scale it
        // about the framed center, bring that center to the window's origin,
        // and push it out in front of the window, since content behind the
        // window plane is hidden by the window.
        let rotation = simd_quatf(angle: orbit.pitch, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: -orbit.yaw, axis: SIMD3(0, 1, 0))
        stage.transform = RealityKit.Transform(
            scale: SIMD3(repeating: stageScale),
            rotation: rotation,
            translation: rotation.act(-stageCenter * stageScale) + SIMD3(0, 0, Self.fittedSize / 2)
        )
        #else
        camera.look(at: orbit.target, from: orbit.position, relativeTo: stage)
        #endif
    }
}

/// The SwiftUI side: a RealityView showing the controller's stage, with
/// drag, pinch, and tap gestures.
struct TouchViewportView: View {
    let controller: TouchViewportController
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.add(controller.stage)
                #if !os(visionOS)
                content.camera = .virtual
                #endif
            }
            .gesture(drag)
            .simultaneousGesture(pinch)
            .simultaneousGesture(tap(in: geometry.size))
        }
        .accessibilityLabel("3D viewport")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDrag.width,
                    height: value.translation.height - lastDrag.height
                )
                lastDrag = value.translation
                controller.orbit(byDragX: delta.width, dragY: delta.height)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                controller.pinch(by: value.magnification / lastMagnification)
                lastMagnification = value.magnification
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    #if os(visionOS)
    /// visionOS delivers taps to the entity looked at; no eye sits inside a
    /// shape there, so SwiftUI's own targeting is enough.
    private func tap(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in controller.pick(value.entity) }
    }
    #else
    private func tap(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in controller.pick(at: value.location, in: size) }
    }
    #endif
}

#endif

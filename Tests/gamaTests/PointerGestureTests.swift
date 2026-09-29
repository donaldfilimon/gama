//  PointerGestureTests.swift — host-owned pointer recognition (ADR 0018):
//  capture, idiom thresholds, long press, cancel paths, hover, legacy
//  `.pointer` compatibility.

import GamaCore
import Testing

/// Records every gesture a pad receives; a class so escaping handlers can
/// append. `accepts` is what handlers return.
private final class GestureLog {
    var entries: [(id: NodeID, gesture: PointerGesture)] = []
    var accepts = true
    var hoveredDuringBuild: NodeID? = nil
    var activated: [NodeID] = []
    var actions: Int { activated.count }
    var focusOnTap: NodeID? = nil

    var phases: [PointerGesture.Phase] { entries.map(\.gesture.phase) }
    func phases(for id: NodeID) -> [PointerGesture.Phase] {
        entries.filter { $0.id == id }.map(\.gesture.phase)
    }
}

/// A primitive interactive pad that opts into pointer gestures.
private struct Pad: View {
    typealias Body = Never_
    var body: Never_ { Never_() }
    let log: GestureLog
    var handles = true
    var dropTarget = false
    var focusable = true
    var width = 6
    var height = 3

    func render(in context: BuildContext) -> RenderNode {
        let id = context.id
        let log = log
        if handles {
            let request = context.requestFocus
            context.registerPointerHandler(id) { gesture in
                log.entries.append((id, gesture))
                if gesture.phase == .tap, let target = log.focusOnTap { request(target) }
                return log.accepts
            }
        }
        if dropTarget { context.registerDropTarget(id) }
        context.registerAction(id) { log.activated.append(id) }
        if context.environment.hoveredID != nil { log.hoveredDuringBuild = context.environment.hoveredID }
        return .interactive(
            id: id, focusable: focusable,
            child: Text("pad").frame(width: width, height: height).render(in: context.child(0)))
    }
}

/// Mutable scene configuration shared between a test and its app value.
private final class PadConfig {
    let log = GestureLog()
    var showFirst = Signal(true)
    var secondIsDropTarget = true
    var firstHandles = true
}

/// Two pads side by side: the first (optionally removable) and a drop target.
private struct PadApp: App {
    let config: PadConfig
    init() { config = PadConfig() }
    init(config: PadConfig) { self.config = config }
    var scenes: some Scene {
        Window("Pads", id: "main", role: .primary) {
            HStack(spacing: 2) {
                if config.showFirst.get() {
                    Pad(log: config.log, handles: config.firstHandles)
                }
                Pad(log: config.log, dropTarget: config.secondIsDropTarget)
            }
        }
    }
}

private let surface = Size(width: 40, height: 10)

/// The interactive regions of the frame `host` just produced.
private func regions(_ frame: LaidOutNode) -> [InteractiveRegion] {
    var out: [InteractiveRegion] = []
    frame.collectInteractive(into: &out)
    return out
}

private func center(_ rect: Rect) -> Point {
    Point(x: rect.minX + rect.size.width / 2, y: rect.minY + rect.size.height / 2)
}

private func down(_ p: Point, at t: UInt64? = 0, id: Int = 0, kind: PointerEvent.Kind = .mouse) -> InputEvent {
    .pointerEvent(PointerEvent(phase: .down, location: p, kind: kind, pointerID: id, timestampMillis: t))
}
private func move(_ p: Point, at t: UInt64? = 1, id: Int = 0, kind: PointerEvent.Kind = .mouse) -> InputEvent {
    .pointerEvent(PointerEvent(phase: .move, location: p, kind: kind, pointerID: id, timestampMillis: t))
}
private func up(_ p: Point, at t: UInt64? = 2, id: Int = 0, kind: PointerEvent.Kind = .mouse) -> InputEvent {
    .pointerEvent(PointerEvent(phase: .up, location: p, kind: kind, pointerID: id, timestampMillis: t))
}
private func offset(_ p: Point, _ dx: Int, _ dy: Int = 0) -> Point { Point(x: p.x + dx, y: p.y + dy) }

@Suite("Pointer event and idiom policy")
struct PointerPolicyTests {
    @Test("a PointerEvent defaults to a primary mouse pointer with no modifiers")
    func eventDefaults() {
        let event = PointerEvent(phase: .down, location: Point(x: 3, y: 4))
        #expect(event.kind == .mouse)
        #expect(event.button == 0)
        #expect(event.pointerID == 0)
        #expect(event.modifiers == [])
        #expect(event.scroll == .zero)
        #expect(event.timestampMillis == nil)
    }

    @Test("the idiom table matches the dock design")
    func idiomTable() {
        #expect(InteractionIdiom.desktop.pointerPolicy
            == PointerPolicy(dragThreshold: 1, longPressMillis: 500, dragRequiresLongPress: false))
        #expect(InteractionIdiom.terminal.pointerPolicy
            == PointerPolicy(dragThreshold: 1, longPressMillis: nil, dragRequiresLongPress: false))
        #expect(InteractionIdiom.pad.pointerPolicy
            == PointerPolicy(dragThreshold: 2, longPressMillis: 400, dragRequiresLongPress: false))
        #expect(InteractionIdiom.phone.pointerPolicy
            == PointerPolicy(dragThreshold: 2, longPressMillis: 500, dragRequiresLongPress: true))
        #expect(InteractionIdiom.vision.pointerPolicy == InteractionIdiom.pad.pointerPolicy)
    }

    @Test("translation follows start and location after mutation")
    func translationIsDerived() {
        var gesture = PointerGesture(phase: .dragMoved, start: Point(x: 1, y: 1), location: Point(x: 4, y: 3))
        #expect(gesture.translation == Point(x: 3, y: 2))
        gesture.location = Point(x: 9, y: 1)
        gesture.start = Point(x: 2, y: 0)
        #expect(gesture.translation == Point(x: 7, y: 1))
    }

    @Test("host-less builds accept every pointer hook as a no-op")
    func hostlessHooks() {
        let context = BuildContext()
        context.registerPointerHandler(.root) { _ in true }
        context.registerDropTarget(.root)
        context.requestFocus(.root)
        #expect(EnvironmentValues().hoveredID == nil)
    }
}

@Suite("Pointer gestures in FrameHost")
struct PointerGestureTests {
    @Test("legacy .pointer still activates a region without a handler on press only")
    func legacyActivateOnPress() throws {
        let config = PadConfig()
        config.firstHandles = false
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        host.handle(.pointer(center(first.frame), pressed: true))
        #expect(config.log.actions == 1)
        host.handle(.pointer(center(first.frame), pressed: false))
        #expect(config.log.actions == 1)
        #expect(config.log.entries.isEmpty)
    }

    @Test("legacy .pointer on a handler region is a press and a tap")
    func legacyOnHandlerIsTap() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        host.handle(.pointer(center(first.frame), pressed: true))
        host.handle(.pointer(center(first.frame), pressed: false))
        #expect(config.log.phases == [.pressed, .tap])
        #expect(config.log.actions == 0)
    }

    @Test("a declined tap falls back to the node's action")
    func declinedTapActivates() throws {
        let config = PadConfig()
        config.log.accepts = false
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        host.handle(down(center(first.frame)))
        host.handle(up(center(first.frame)))
        #expect(config.log.phases == [.pressed, .tap])
        #expect(config.log.actions == 1)
    }

    @Test("a declined tap from a non-primary button does not activate")
    func declinedSecondaryTapDoesNotActivate() throws {
        let config = PadConfig()
        config.log.accepts = false
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        let p = center(first.frame)
        host.handle(.pointerEvent(PointerEvent(phase: .down, location: p, button: 1, timestampMillis: 0)))
        host.handle(.pointerEvent(PointerEvent(phase: .up, location: p, button: 1, timestampMillis: 1)))
        #expect(config.log.phases == [.pressed, .tap])
        #expect(config.log.actions == 0)
    }

    @Test("a second button pressed during a capture is ignored, press and release")
    func chordedButtonIgnored() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        let p = center(first.frame)
        host.handle(.pointerEvent(PointerEvent(phase: .down, location: p, button: 0, timestampMillis: 0)))
        host.handle(.pointerEvent(PointerEvent(phase: .down, location: p, button: 1, timestampMillis: 1)))
        host.handle(.pointerEvent(PointerEvent(phase: .up, location: p, button: 1, timestampMillis: 2)))
        #expect(config.log.phases == [.pressed])
        host.handle(.pointerEvent(PointerEvent(phase: .up, location: p, button: 0, timestampMillis: 3)))
        #expect(config.log.phases == [.pressed, .tap])
        #expect(config.log.entries.allSatisfy { $0.gesture.button == 0 })
    }

    @Test("the same button pressed again during a capture cancels the lost gesture")
    func sameButtonRepressCancels() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        let p = center(first.frame)
        host.handle(down(p))
        host.handle(down(p, at: 1))
        host.handle(up(p))
        #expect(config.log.phases == [.pressed, .cancelled, .pressed, .tap])
    }

    @Test("a mouse release outside the surface clears hover")
    func releaseOutsideClearsHover() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        let p = center(first.frame)
        host.handle(.pointerEvent(PointerEvent(phase: .hover, location: p)))
        host.handle(down(p))
        // The view's exit notice arrives while the button is held.
        host.handle(.pointerEvent(PointerEvent(phase: .hover, location: Point(x: -1, y: -1))))
        host.handle(up(Point(x: -1, y: -1)))
        let dirty = host.needsFrame
        #expect(dirty)
        config.log.hoveredDuringBuild = nil
        _ = host.pump(size: surface)
        #expect(config.log.hoveredDuringBuild == nil)
    }

    @Test("movement at the idiom threshold begins a drag", arguments: [
        (InteractionIdiom.desktop, 1), (.terminal, 1), (.pad, 2), (.vision, 2),
    ])
    func dragThreshold(idiom: InteractionIdiom, threshold: Int) throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config), idiom: idiom)
        let first = regions(host.pump(size: surface))[0]
        let start = Point(x: first.frame.minX, y: first.frame.minY)
        host.handle(down(start))
        host.handle(move(offset(start, threshold - 1)))
        #expect(config.log.phases == [.pressed])
        host.handle(move(offset(start, threshold)))
        host.handle(move(offset(start, threshold + 3)))
        host.handle(up(offset(start, threshold + 3)))
        #expect(config.log.phases == [.pressed, .dragBegan, .dragMoved, .dragEnded])
        let ended = config.log.entries.last!.gesture
        #expect(ended.start == start)
        #expect(ended.translation == Point(x: threshold + 3, y: 0))
    }

    @Test("capture: a drag keeps reaching its region outside it; other pointers are ignored")
    func captureAndSecondPointer() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let pads = regions(host.pump(size: surface))
        let start = center(pads[0].frame)
        host.handle(down(start))
        host.handle(down(center(pads[1].frame), id: 7))
        host.handle(move(center(pads[1].frame)))
        host.handle(up(Point(x: 39, y: 9)))
        #expect(config.log.phases(for: pads[0].id) == [.pressed, .dragBegan, .dragEnded])
        #expect(config.log.phases(for: pads[1].id).isEmpty)
    }

    @Test("drag phases carry the drop target under the pointer")
    func dropTarget() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let pads = regions(host.pump(size: surface))
        host.handle(down(center(pads[0].frame)))
        host.handle(move(offset(center(pads[0].frame), 1)))
        host.handle(move(center(pads[1].frame)))
        host.handle(up(center(pads[1].frame)))
        let targets = config.log.entries.map(\.gesture.dropTarget)
        #expect(targets == [nil, nil, pads[1].id, pads[1].id])
    }

    @Test("long press: the deadline fires once on a stationary sample, and release cancels")
    func longPress() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        host.handle(down(center(first.frame), at: 1_000))
        let deadline = host.pointerDeadlineMillis
        #expect(deadline == 1_500)
        host.handle(.pointerEvent(PointerEvent(phase: .stationary, location: center(first.frame), timestampMillis: 1_499)))
        #expect(config.log.phases == [.pressed])
        host.handle(.pointerEvent(PointerEvent(phase: .stationary, location: center(first.frame), timestampMillis: 1_500)))
        #expect(config.log.phases == [.pressed, .longPress])
        host.handle(.pointerEvent(PointerEvent(phase: .stationary, location: center(first.frame), timestampMillis: 1_600)))
        let cleared = host.pointerDeadlineMillis
        #expect(cleared == nil)
        host.handle(up(center(first.frame), at: 1_700))
        #expect(config.log.phases == [.pressed, .longPress, .cancelled])
        #expect(config.log.actions == 0)
    }

    @Test("terminal has no long-press deadline")
    func terminalNoLongPress() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config), idiom: .terminal)
        let first = regions(host.pump(size: surface))[0]
        host.handle(down(center(first.frame), at: 1_000))
        let deadline = host.pointerDeadlineMillis
        #expect(deadline == nil)
        host.handle(up(center(first.frame), at: 9_000))
        #expect(config.log.phases == [.pressed, .tap])
    }

    @Test("a release past the deadline without a sample is still a long press")
    func lateReleaseIsLongPress() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config), idiom: .pad)
        let first = regions(host.pump(size: surface))[0]
        host.handle(down(center(first.frame), at: 0, kind: .touch))
        host.handle(up(center(first.frame), at: 400, kind: .touch))
        #expect(config.log.phases == [.pressed, .longPress, .cancelled])
    }

    @Test("phone: movement before the long press cancels; after it, drags")
    func phoneDragNeedsLongPress() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config), idiom: .phone)
        let first = regions(host.pump(size: surface))[0]
        let start = Point(x: first.frame.minX, y: first.frame.minY)
        host.handle(down(start, at: 0, kind: .touch))
        host.handle(move(offset(start, 2), at: 100, kind: .touch))
        #expect(config.log.phases == [.pressed, .cancelled])
        host.handle(up(offset(start, 2), at: 200, kind: .touch))
        #expect(config.log.phases == [.pressed, .cancelled])

        config.log.entries.removeAll()
        host.handle(down(start, at: 1_000, kind: .touch))
        host.handle(move(start, at: 1_500, kind: .touch))
        host.handle(move(offset(start, 2), at: 1_600, kind: .touch))
        host.handle(up(offset(start, 2), at: 1_700, kind: .touch))
        #expect(config.log.phases == [.pressed, .longPress, .dragBegan, .dragEnded])
    }

    @Test("explicit cancel, Escape and a resign-key event each cancel exactly once")
    func cancelPaths() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        let p = center(first.frame)
        let sceneID = host.sceneID
        let instance = host.windowInstanceID
        let cancels: [InputEvent] = [
            .pointerEvent(PointerEvent(phase: .cancel, location: p)),
            .key(.escape),
            .lifecycle(.windowDidResignKey(scene: sceneID, instance: instance)),
            .lifecycle(.didEnterBackground),
        ]
        for cancel in cancels {
            config.log.entries.removeAll()
            host.handle(down(p))
            host.handle(move(offset(p, 1)))
            host.handle(cancel)
            host.handle(up(offset(p, 1)))
            #expect(config.log.phases == [.pressed, .dragBegan, .cancelled])
            let deadline = host.pointerDeadlineMillis
            #expect(deadline == nil)
        }
    }

    @Test("Escape without a capture still reaches the key path")
    func escapeWithoutCapture() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        _ = host.pump(size: surface)
        host.handle(.key(.escape))
        #expect(config.log.entries.isEmpty)
    }

    @Test("a captured node vanishing on rebuild is cancelled through its last handler")
    func vanishedNodeCancels() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        host.handle(down(center(first.frame)))
        config.showFirst.set(false)
        _ = host.pump(size: surface)
        #expect(config.log.phases(for: first.id) == [.pressed, .cancelled])
        host.handle(up(center(first.frame)))
        #expect(config.log.phases(for: first.id) == [.pressed, .cancelled])
    }

    @Test("every press ends in exactly one terminal phase")
    func terminalPhaseInvariant() throws {
        let terminal: Set<PointerGesture.Phase> = [.tap, .dragEnded, .cancelled]
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let p = center(regions(host.pump(size: surface))[0].frame)
        let sequences: [[InputEvent]] = [
            [down(p), up(p)],
            [down(p), move(offset(p, 2)), up(offset(p, 2))],
            [down(p), up(offset(p, 3))],
            [down(p, at: 0), up(p, at: 600)],
            [down(p), .key(.escape), up(p)],
            [down(p), down(p), up(p)],
        ]
        for sequence in sequences {
            config.log.entries.removeAll()
            for event in sequence { host.handle(event) }
            let pressed = config.log.phases.filter { $0 == .pressed }.count
            let ended = config.log.phases.filter { terminal.contains($0) }.count
            #expect(pressed == ended, "\(config.log.phases)")
        }
    }

    @Test("hover reaches the environment and dirties the host only on change")
    func hoverDirtiness() throws {
        let config = PadConfig()
        config.log.accepts = false
        var host = try FrameHost(app: PadApp(config: config))
        let pads = regions(host.pump(size: surface))
        let hover = { (p: Point) in InputEvent.pointerEvent(PointerEvent(phase: .hover, location: p)) }

        host.handle(hover(center(pads[0].frame)))
        let dirtyOnEnter = host.needsFrame
        #expect(dirtyOnEnter)
        _ = host.pump(size: surface)
        #expect(config.log.hoveredDuringBuild == pads[0].id)

        host.handle(hover(offset(center(pads[0].frame), 1)))
        let dirtyOnSame = host.needsFrame
        #expect(!dirtyOnSame)

        host.handle(hover(center(pads[1].frame)))
        let dirtyOnChange = host.needsFrame
        #expect(dirtyOnChange)
        _ = host.pump(size: surface)
        #expect(config.log.hoveredDuringBuild == pads[1].id)
        #expect(config.log.phases.allSatisfy { $0 == .hover })
    }

    @Test("an untracked mouse move is hover; a vanished hovered node clears")
    func moveIsHoverAndVanishClears() throws {
        let config = PadConfig()
        config.log.accepts = false
        var host = try FrameHost(app: PadApp(config: config))
        let first = regions(host.pump(size: surface))[0]
        host.handle(move(center(first.frame)))
        let dirty = host.needsFrame
        #expect(dirty)
        config.showFirst.set(false)
        _ = host.pump(size: surface)
        config.log.hoveredDuringBuild = nil
        host.invalidate()
        _ = host.pump(size: surface)
        #expect(config.log.hoveredDuringBuild == nil)
    }

    @Test("scroll reaches the handler region under the pointer with its delta")
    func scroll() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let pads = regions(host.pump(size: surface))
        host.handle(.pointerEvent(PointerEvent(
            phase: .scroll, location: center(pads[1].frame), modifiers: [.shift], scroll: Point(x: 0, y: -3))))
        #expect(config.log.phases(for: pads[1].id) == [.scroll])
        let gesture = config.log.entries[0].gesture
        #expect(gesture.scroll == Point(x: 0, y: -3))
        #expect(gesture.modifiers == [.shift])
        let dirty = host.needsFrame
        #expect(dirty)
    }

    @Test("requestFocus from a handler moves focus on the next pump")
    func requestFocus() throws {
        let config = PadConfig()
        var host = try FrameHost(app: PadApp(config: config))
        let pads = regions(host.pump(size: surface))
        config.log.focusOnTap = pads[1].id
        // Press the second pad through the legacy path would focus it
        // directly; tap the first instead so only the request can move focus
        // to the second.
        host.handle(down(center(pads[0].frame)))
        host.handle(up(center(pads[0].frame)))
        let dirty = host.needsFrame
        #expect(dirty)
        _ = host.pump(size: surface)
        config.log.entries.removeAll()
        config.log.focusOnTap = nil
        host.handle(.key(.enter))
        #expect(config.log.activated == [pads[1].id])
        host.handle(down(center(pads[1].frame)))
        host.handle(up(center(pads[1].frame)))
        #expect(config.log.phases(for: pads[1].id) == [.pressed, .tap])
    }
}

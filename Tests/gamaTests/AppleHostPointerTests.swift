//  AppleHostPointerTests.swift — AppKit pointer translation (ADR 0018,
//  dock phase 2): real NSEvents through a windowed host reach FrameHost's
//  recognizer as raw samples, and the long-press timer follows the host's
//  published deadline.

#if canImport(AppKit)
    import AppKit
    @testable import GamaAppleUI
    import GamaCore
    import Testing

    /// Records every gesture the pad receives; a class so the escaping
    /// handler can append.
    private final class AppleGestureLog {
        var gestures: [PointerGesture] = []
        var phases: [PointerGesture.Phase] { gestures.map(\.phase) }
    }

    /// A 6x3 pad that opts into pointer gestures.
    private struct ApplePad: View {
        typealias Body = Never_
        var body: Never_ { Never_() }
        let log: AppleGestureLog

        func render(in context: BuildContext) -> RenderNode {
            let id = context.id
            let log = log
            context.registerPointerHandler(id) { gesture in
                log.gestures.append(gesture)
                return true
            }
            return .interactive(
                id: id, focusable: true,
                child: Text("pad").frame(width: 6, height: 3).render(in: context.child(0)))
        }
    }

    private struct ApplePadApp: App {
        let log: AppleGestureLog
        init() { log = AppleGestureLog() }
        init(log: AppleGestureLog) { self.log = log }
        var scenes: some Scene {
            Window("Pad", id: "main", role: .primary) { ApplePad(log: log) }
        }
    }

    @Suite("AppKit host pointer translation")
    @MainActor
    struct AppleHostPointerTests {
        /// A windowed host with the pad installed and laid out, so
        /// `locationInWindow` converts the way it does in an app.
        private func windowedHost(_ log: AppleGestureLog) throws -> (GamaHostView, NSWindow) {
            let host = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
            try host.install(app: ApplePadApp(log: log))
            let window = NSWindow(
                contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            host.invalidate()
            return (host, window)
        }

        /// An event at the center of grid cell `cell`, in window coordinates.
        private func event(
            _ type: NSEvent.EventType, at cell: Point, in host: GamaHostView, window: NSWindow,
            seconds: TimeInterval, modifiers: NSEvent.ModifierFlags = []
        ) throws -> NSEvent {
            let local = NSPoint(
                x: (CGFloat(cell.x) + 0.5) * host.cellSize.width,
                y: (CGFloat(cell.y) + 0.5) * host.cellSize.height)
            return try #require(
                NSEvent.mouseEvent(
                    with: type, location: host.convert(local, to: nil), modifierFlags: modifiers,
                    timestamp: seconds, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
        }

        @Test("a mouse drag becomes pressed, dragBegan, dragEnded at the right cells")
        func dragThroughNSEvents() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            host.mouseDown(with: try event(.leftMouseDown, at: Point(x: 1, y: 1), in: host, window: window, seconds: 100))
            host.mouseDragged(with: try event(.leftMouseDragged, at: Point(x: 4, y: 1), in: host, window: window, seconds: 100.05))
            // Past the right edge of the pad: capture keeps the samples coming.
            host.mouseDragged(with: try event(.leftMouseDragged, at: Point(x: 12, y: 2), in: host, window: window, seconds: 100.1))
            host.mouseUp(with: try event(.leftMouseUp, at: Point(x: 12, y: 2), in: host, window: window, seconds: 100.15))

            #expect(log.phases == [.pressed, .dragBegan, .dragMoved, .dragEnded])
            #expect(log.gestures.first?.start == Point(x: 1, y: 1))
            #expect(log.gestures.last?.location == Point(x: 12, y: 2))
            #expect(log.gestures.last?.translation == Point(x: 11, y: 1))
        }

        @Test("the secondary button and modifier flags reach the sample")
        func rightButtonAndModifiers() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            host.rightMouseDown(with: try event(
                .rightMouseDown, at: Point(x: 2, y: 1), in: host, window: window, seconds: 5,
                modifiers: [.shift, .command]))
            host.rightMouseUp(with: try event(.rightMouseUp, at: Point(x: 2, y: 1), in: host, window: window, seconds: 5.01))
            #expect(log.phases == [.pressed, .tap])
            #expect(log.gestures.first?.button == 1)
            #expect(log.gestures.first?.modifiers == [.shift, .command])
        }

        @Test("the long-press timer is armed at the host's deadline and delivers a stationary sample")
        func longPressTimer() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            #expect(host.armedPointerDeadlineMillis == nil)
            host.mouseDown(with: try event(.leftMouseDown, at: Point(x: 1, y: 1), in: host, window: window, seconds: 100))
            // NSEvent.timestamp is seconds since boot; desktop long press is 500 ms.
            #expect(host.armedPointerDeadlineMillis == 100_500)
            host.deliverPointerDeadline()
            #expect(log.phases == [.pressed, .longPress])
            #expect(host.armedPointerDeadlineMillis == nil)
            host.mouseUp(with: try event(.leftMouseUp, at: Point(x: 1, y: 1), in: host, window: window, seconds: 101))
            #expect(log.phases == [.pressed, .longPress, .cancelled])
        }

        @Test("a second button during a press neither ends it nor drops its long-press sample")
        func chordedButtonKeepsPress() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            host.mouseDown(with: try event(.leftMouseDown, at: Point(x: 1, y: 1), in: host, window: window, seconds: 9))
            host.rightMouseDown(with: try event(.rightMouseDown, at: Point(x: 1, y: 1), in: host, window: window, seconds: 9.1))
            host.rightMouseUp(with: try event(.rightMouseUp, at: Point(x: 1, y: 1), in: host, window: window, seconds: 9.2))
            #expect(log.phases == [.pressed])
            host.deliverPointerDeadline()
            #expect(log.phases == [.pressed, .longPress])
            host.mouseUp(with: try event(.leftMouseUp, at: Point(x: 1, y: 1), in: host, window: window, seconds: 10))
            #expect(log.phases == [.pressed, .longPress, .cancelled])
        }

        @Test("the long-press timer fires while the run loop is in an event-tracking mode")
        func longPressTimerFiresInTrackingMode() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            // A press far in the past: its deadline is already due, so the
            // timer is armed with a zero delay.
            host.mouseDown(with: try event(.leftMouseDown, at: Point(x: 1, y: 1), in: host, window: window, seconds: 1))
            let armed = host.armedPointerDeadlineMillis
            #expect(armed == 1_500)
            // `run(mode:before:)` returns after the first input source, and
            // timers do not count as one, so spin until the timer has fired.
            let end = Date(timeIntervalSinceNow: 1)
            while host.armedPointerDeadlineMillis != nil, Date() < end {
                RunLoop.main.run(mode: .eventTracking, before: end)
            }
            #expect(log.phases == [.pressed, .longPress])
        }

        @Test("a release before the deadline disarms the timer")
        func releaseDisarms() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            host.mouseDown(with: try event(.leftMouseDown, at: Point(x: 1, y: 1), in: host, window: window, seconds: 7))
            #expect(host.armedPointerDeadlineMillis == 7_500)
            host.mouseUp(with: try event(.leftMouseUp, at: Point(x: 1, y: 1), in: host, window: window, seconds: 7.1))
            #expect(host.armedPointerDeadlineMillis == nil)
            host.deliverPointerDeadline()
            #expect(log.phases == [.pressed, .tap])
        }

        @Test("Escape cancels the press and disarms the timer through the key route")
        func escapeDisarms() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            host.mouseDown(with: try event(.leftMouseDown, at: Point(x: 1, y: 1), in: host, window: window, seconds: 9))
            #expect(host.armedPointerDeadlineMillis == 9_500)
            let escape = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 9.1,
                    windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                    charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
            host.keyDown(with: escape)
            #expect(log.phases == [.pressed, .cancelled])
            #expect(host.armedPointerDeadlineMillis == nil)
        }

        @Test("hover over the pad reaches its handler")
        func hover() throws {
            let log = AppleGestureLog()
            let (host, window) = try windowedHost(log)
            host.mouseMoved(with: try event(.mouseMoved, at: Point(x: 3, y: 2), in: host, window: window, seconds: 1))
            #expect(log.phases == [.hover])
            #expect(log.gestures.first?.location == Point(x: 3, y: 2))
        }

        @Test("AppKit scroll deltas accumulate into Gama's sign: positive rows reveal the lines below")
        func scrollConvention() {
            let cell = CGSize(width: 8, height: 16)
            var remainder = CGSize.zero
            // A precise trackpad swipe revealing the content below reports a
            // negative scrollingDeltaY: 1.5 cells, then another half cell.
            #expect(GamaHostView.scrollCells(
                deltaX: 0, deltaY: -24, precise: true, cellSize: cell, remainder: &remainder)
                == Point(x: 0, y: 1))
            #expect(GamaHostView.scrollCells(
                deltaX: 0, deltaY: -8, precise: true, cellSize: cell, remainder: &remainder)
                == Point(x: 0, y: 1))
            // A classic wheel reports lines: one line toward the user is -1.
            var lines = CGSize.zero
            #expect(GamaHostView.scrollCells(
                deltaX: 0, deltaY: -1, precise: false, cellSize: cell, remainder: &lines)
                == Point(x: 0, y: 1))
            #expect(GamaHostView.scrollCells(
                deltaX: 2, deltaY: 0, precise: false, cellSize: cell, remainder: &lines)
                == Point(x: -2, y: 0))
        }
    }
#endif

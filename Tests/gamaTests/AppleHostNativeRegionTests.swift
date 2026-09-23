#if canImport(AppKit)
    import AppKit
    import GamaAppleUI
    import GamaCore
    import Testing

    @Suite("AppKit host native regions")
    @MainActor
    struct AppleHostNativeRegionTests {
        private struct ViewportApp: App {
            let show = Signal(true)
            var scenes: some Scene {
                Window("Studio", id: "main", role: .primary) {
                    VStack {
                        Button("Panel") {}
                        NativeRegion(NativeRegionID("viewport")) { Text("3D viewport") }
                            .frame(width: show.get() ? 20 : 0, height: show.get() ? 5 : 0)
                    }
                }
            }
        }

        private struct TwoRegionApp: App {
            var scenes: some Scene {
                Window("Studio", id: "main", role: .primary) {
                    VStack {
                        NativeRegion(NativeRegionID("a")) { Text("A") }
                            .frame(width: 10, height: 5)
                        NativeRegion(NativeRegionID("b")) { Text("B") }
                            .frame(width: 10, height: 5)
                    }
                }
            }
        }

        private func installed<A: App>(_ app: A) throws -> GamaHostView {
            let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
            try view.install(app: app)
            view.layoutSubtreeIfNeeded()
            view.invalidate()
            return view
        }

        @Test("an attached view is placed on the region's frame and shown")
        func placedAndShown() throws {
            let host = try installed(ViewportApp())
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            #expect(native.superview === host)
            #expect(native.isHidden == false)
            #expect(native.frame.width > 0 && native.frame.height > 0)
            #expect(host.isCoveredByNativeRegion(Rect(origin: Point(x: Int(native.frame.minX / host.cellSize.width), y: Int(native.frame.minY / host.cellSize.height)), size: Size(width: 1, height: 1))))
        }

        @Test("the view hides when its region goes away and stays attached")
        func hidesWhenAbsent() throws {
            let app = ViewportApp()
            let host = try installed(app)
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            app.show.set(false)
            host.invalidate()
            #expect(native.isHidden == true)
            #expect(native.superview === host)
        }

        @Test("re-attaching replaces the view and detach removes it")
        func replaceAndDetach() throws {
            let host = try installed(ViewportApp())
            let first = NSView(), second = NSView()
            host.attach(first, to: NativeRegionID("viewport"))
            host.attach(second, to: NativeRegionID("viewport"))
            #expect(first.superview == nil)
            #expect(second.superview === host)
            host.detach(NativeRegionID("viewport"))
            #expect(second.superview == nil)
        }

        @Test("Gama focus on the region makes the attached view first responder")
        func focusHandoff() throws {
            let host = try installed(ViewportApp())
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = host
            let native = FocusableView()
            host.attach(native, to: NativeRegionID("viewport"))
            host.send(.key(.tab))  // button → region
            #expect(window.firstResponder === native)
            host.send(.key(.tab))  // region → button: host reclaims
            #expect(window.firstResponder === host)
        }

        @Test("focus moving from one native region straight to another hands off without the host reclaiming first responder")
        func focusHandoffBetweenRegions() throws {
            let host = try installed(TwoRegionApp())
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = host
            let viewA = FocusableView()
            let viewB = FocusableView()
            host.attach(viewA, to: NativeRegionID("a"))
            host.attach(viewB, to: NativeRegionID("b"))
            // Region "a" is the first focusable node, so Gama's initial
            // focus already lands there without a Tab.
            #expect(window.firstResponder === viewA)
            host.send(.key(.tab))  // region a → region b, directly
            #expect(window.firstResponder === viewB)
        }

        @Test("a frame update after focus moved elsewhere does not steal first responder back")
        func focusReclaimDoesNotStealFromUnrelatedControl() throws {
            let host = try installed(ViewportApp())
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = host
            let native = FocusableView()
            host.attach(native, to: NativeRegionID("viewport"))
            host.send(.key(.tab))  // button → region
            #expect(window.firstResponder === native)

            let other = FocusableView()
            host.addSubview(other)
            _ = window.makeFirstResponder(other)
            #expect(window.firstResponder === other)

            host.send(.key(.tab))  // region → button: Gama focus leaves the region
            #expect(window.firstResponder === other)
        }

        @Test("an attached view is an accessibility child between the rows")
        func accessibilityChild() throws {
            let host = try installed(ViewportApp())
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            let children = host.accessibilityChildren() ?? []
            #expect(children.contains { ($0 as AnyObject) === native })
        }

        private final class FocusableView: NSView {
            override var acceptsFirstResponder: Bool { true }
        }
    }
#endif

#if canImport(AppKit)
    import AppKit
    import GamaAppleUI
    import GamaCore
    import GamaDraw
    import Testing

    /// The AppKit half of the VoiceOver work. The reading-order derivation is
    /// proved portably in `AccessibilitySnapshotTests`; what is proved here is
    /// the bridge — that the host publishes itself as a container, that each
    /// non-blank row becomes one static-text child framed in view coordinates,
    /// and that the cache actually tracks frames instead of going stale.
    @Suite("AppKit host accessibility")
    @MainActor
    struct AppleHostAccessibilityTests {
        private struct LabelledApp: App {
            var scenes: some Scene {
                Window("Accessible", id: "main", role: .primary) {
                    VStack {
                        Text("Alpha row")
                        Text("Beta row")
                    }
                }
            }
        }

        private struct ReplacementApp: App {
            var scenes: some Scene {
                Window("Replacement", id: "main", role: .primary) {
                    Text("Gamma row")
                }
            }
        }

        private func installedView() throws -> GamaHostView {
            let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
            try view.install(app: LabelledApp())
            view.layoutSubtreeIfNeeded()
            view.invalidate()
            return view
        }

        @Test("the host is a container, not one opaque element")
        func hostIsAContainer() throws {
            let view = try installedView()
            #expect(view.isAccessibilityElement() == false)
            #expect(view.accessibilityRole() == .group)
            #expect(view.accessibilityLabel() == "Gama surface")
        }

        @Test("each rendered row becomes one static-text child")
        func rowsBecomeStaticTextChildren() throws {
            let view = try installedView()
            let children = try #require(view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            #expect(!children.isEmpty)
            #expect(children.count == view.accessibilitySnapshot.lines.count)
            for child in children {
                #expect(child.accessibilityRole() == .staticText)
            }
            let values = children.compactMap { $0.accessibilityValue() as? String }
            #expect(values.contains { $0.contains("Alpha row") })
            #expect(values.contains { $0.contains("Beta row") })
        }

        @Test("children read in top-to-bottom order")
        func childrenAreInReadingOrder() throws {
            let view = try installedView()
            let children = try #require(view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            let rows = children.map(\.line.frame.minY)
            #expect(rows == rows.sorted())
        }

        @Test("a child's frame is its grid cells scaled by the measured cell size")
        func childFrameMatchesItsCells() throws {
            let view = try installedView()
            let children = try #require(view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            let child = try #require(children.first)
            let frame = child.accessibilityFrameInParentSpace()
            let cells = child.line.frame
            // The exact cell size is a measured font metric, so assert the
            // relationship rather than a hardcoded number: a one-row element
            // is one cell tall, and its width is its column count times the
            // same unit height-for-width ratio the host used.
            #expect(frame.height > 0)
            #expect(frame.width > 0)
            let unitWidth = frame.width / CGFloat(cells.size.width)
            #expect(abs(frame.minX - CGFloat(cells.minX) * unitWidth) < 0.001)
            #expect(abs(frame.minY - CGFloat(cells.minY) * frame.height) < 0.001)
        }

        @Test("the snapshot is cached between queries and refreshed after a new frame")
        func snapshotCacheTracksFrames() throws {
            let view = try installedView()
            let first = view.accessibilitySnapshot
            // No frame in between: the identical value proves the cache is
            // returning, not that the derivation happens to be deterministic —
            // the element objects are rebuilt only when the frame changes.
            let firstChildren = try #require(
                view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            let cachedChildren = try #require(
                view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            #expect(view.accessibilitySnapshot == first)
            #expect(zip(firstChildren, cachedChildren).allSatisfy { $0 === $1 })

            try view.install(app: ReplacementApp())
            view.invalidate()
            let second = view.accessibilitySnapshot
            #expect(second != first)
            #expect(second.lines.contains { $0.text.contains("Gamma row") })
            #expect(!second.lines.contains { $0.text.contains("Alpha row") })
            let replacedChildren = try #require(
                view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            #expect(zip(firstChildren, replacedChildren).allSatisfy { $0 !== $1 })
        }

        @Test("an uninstalled host publishes no children rather than trapping")
        func emptyHostHasNoChildren() {
            let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
            #expect(view.accessibilitySnapshot.lines.isEmpty)
            let children = view.accessibilityChildren() as? [GamaAccessibilityLineElement]
            #expect(children?.isEmpty == true)
        }

        @Test("frames cost nothing until an accessibility client asks")
        func noAccessibilityWorkBeforeAQuery() throws {
            let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
            try view.install(app: LabelledApp())
            view.layoutSubtreeIfNeeded()
            view.invalidate()
            // Frames have been produced, but nothing has been derived or
            // announced, because no client has touched the view.
            #expect(view.accessibilityIsObserved == false)
            #expect(view.accessibilityAnnouncedSnapshot == nil)

            _ = view.accessibilityChildren()
            #expect(view.accessibilityIsObserved)

            // Now that a client is attached, the next frame announces.
            try view.install(app: ReplacementApp())
            view.invalidate()
            let announced = try #require(view.accessibilityAnnouncedSnapshot)
            #expect(announced.lines.contains { $0.text.contains("Gamma row") })
        }

        @Test("the published text is the frame's text, not a second model of it")
        func publishedTextMatchesTheDrawList() throws {
            let view = try installedView()
            #expect(view.accessibilitySnapshot == AccessibilitySnapshot.from(view.currentDrawList))
        }
    }
#endif

#if canImport(AppKit)
    import AppKit
    import GamaAppleUI
    import GamaCore
    import GamaDraw
    import Testing

    /// Pins phase 1 of the UI scaling design
    /// (`docs/superpowers/specs/2026-09-29-ui-scaling-design.md`): the Apple
    /// host's text size is a property, scale stays in cells, and a change
    /// refits the grid instead of clipping it.
    ///
    /// Font metrics are measured, not constants, so every assertion compares
    /// against the host's own `cellSize` or an independently measured probe
    /// rather than a hardcoded point value.
    @Suite("AppKit host font scale")
    @MainActor
    struct AppleHostFontScaleTests {
        private struct LabelledApp: App {
            var scenes: some Scene {
                Window("Scaled", id: "main", role: .primary) {
                    VStack {
                        Text("Alpha row")
                        Text("Beta row")
                    }
                }
            }
        }

        private static let frame = NSRect(x: 0, y: 0, width: 420, height: 180)

        private func installedView() throws -> GamaHostView {
            let view = GamaHostView(frame: Self.frame)
            try view.install(app: LabelledApp())
            view.layoutSubtreeIfNeeded()
            view.invalidate()
            return view
        }

        /// The cell size the host should measure at `size`: the same "M"
        /// probe, rounded up, against an independently built font.
        private static func expectedCellSize(at size: CGFloat) -> CGSize {
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let probe = NSAttributedString(string: "M", attributes: [.font: font]).size()
            return CGSize(width: ceil(probe.width), height: ceil(probe.height))
        }

        private static func grid(_ bounds: CGRect, _ cell: CGSize) -> Size {
            Size(
                width: max(1, Int(bounds.width / cell.width)),
                height: max(1, Int(bounds.height / cell.height)))
        }

        @Test("the default text size is 14 points")
        func defaultSizeIsFourteen() {
            let view = GamaHostView(frame: Self.frame)
            #expect(view.fontPointSize == 14)
            #expect(view.cellSize == Self.expectedCellSize(at: 14))
        }

        @Test("a new size re-measures the cell, shrinks the grid, and pumps one frame")
        func newSizeRefitsTheGrid() throws {
            let view = try installedView()
            let before = view.cellSize
            let gridBefore = view.currentDrawList.size
            let framesBefore = view.producedFrameCount

            // A jump large enough that the integer grid must change: a 1 pt
            // step can leave `bounds / ceil(cell)` identical.
            view.fontPointSize = 28

            #expect(view.cellSize == Self.expectedCellSize(at: 28))
            #expect(view.cellSize.width > before.width)
            #expect(view.cellSize.height > before.height)
            // No layout pass and no invalidate: the setter alone resized.
            let expectedGrid = Self.grid(view.bounds, view.cellSize)
            #expect(view.currentDrawList.size == expectedGrid)
            #expect(expectedGrid.width < gridBefore.width)
            #expect(expectedGrid.height < gridBefore.height)
            #expect(view.producedFrameCount == framesBefore + 1)
        }

        // Redraw requests are counted rather than read from `needsDisplay`:
        // AppKit neither keeps that flag on a windowless view nor clears it
        // on an offscreen window, so it cannot distinguish a no-op.

        @Test("setting the current size again is a no-op")
        func sameSizeIsANoOp() throws {
            let view = try installedView()
            view.fontPointSize = 20
            let cell = view.cellSize
            let frames = view.producedFrameCount
            let redraws = view.redrawRequestCount

            view.fontPointSize = 20

            #expect(view.cellSize == cell)
            #expect(view.producedFrameCount == frames)
            #expect(view.redrawRequestCount == redraws)
        }

        @Test("a size change always requests a redraw, even when the grid is unchanged")
        func sizeChangeRedrawsEvenWithoutAGridChange() throws {
            // A one-point view is a 1x1 grid at every text size, so the
            // resize leaves the grid as it was; the glyphs still changed size
            // and must be redrawn whatever the pump decides.
            let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            try view.install(app: LabelledApp())
            let grid = view.currentDrawList.size
            let redraws = view.redrawRequestCount

            view.fontPointSize = 30

            #expect(view.currentDrawList.size == grid)
            #expect(view.redrawRequestCount > redraws)
        }

        @Test("hosts at one size share a font; different sizes do not")
        func fontsAreSharedPerSize() {
            let first = GamaHostView(frame: Self.frame)
            let second = GamaHostView(frame: Self.frame)
            let third = GamaHostView(frame: Self.frame)
            first.fontPointSize = 22
            second.fontPointSize = 22
            third.fontPointSize = 18

            #expect(first.baseFontIdentifier == second.baseFontIdentifier)
            #expect(first.baseFontIdentifier != third.baseFontIdentifier)

            // Returning to the default rejoins the default hosts' font.
            let untouched = GamaHostView(frame: Self.frame)
            third.fontPointSize = 14
            #expect(third.baseFontIdentifier == untouched.baseFontIdentifier)
        }

        @Test("a size change clears the styled-font cache")
        func sizeChangeClearsStyledCache() {
            let view = GamaHostView(frame: Self.frame)
            for attributes in [[], [.bold], [.italic], [.bold, .italic]] as [TextAttributes] {
                _ = view.styledFont(for: TextStyle(attributes: attributes))
            }
            #expect(view.styledFontCacheCount == 4)

            view.fontPointSize = 24

            #expect(view.styledFontCacheCount == 0)
            let bold = view.styledFont(for: TextStyle(attributes: [.bold]))
            #expect(bold.pointSize == 24)
        }

        @Test("accessibility rectangles use the new cell size")
        func accessibilityFramesFollowTheCellSize() throws {
            let view = try installedView()
            // Query first so the host arms its accessibility cache.
            let before = try #require(view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            let firstBefore = try #require(before.first)
            #expect(firstBefore.accessibilityFrameInParentSpace().height == view.cellSize.height)

            view.fontPointSize = 28

            let after = try #require(view.accessibilityChildren() as? [GamaAccessibilityLineElement])
            let child = try #require(after.first)
            let frame = child.accessibilityFrameInParentSpace()
            let cells = child.line.frame
            #expect(frame.height == CGFloat(cells.size.height) * view.cellSize.height)
            #expect(frame.width == CGFloat(cells.size.width) * view.cellSize.width)
            #expect(frame.minX == CGFloat(cells.minX) * view.cellSize.width)
            #expect(frame.minY == CGFloat(cells.minY) * view.cellSize.height)
        }

        @Test("the size is clamped to 6...72 at both ends")
        func sizeIsClamped() {
            let view = GamaHostView(frame: Self.frame)
            view.fontPointSize = 1
            #expect(view.fontPointSize == 6)
            #expect(view.cellSize == Self.expectedCellSize(at: 6))

            view.fontPointSize = 500
            #expect(view.fontPointSize == 72)
            #expect(view.cellSize == Self.expectedCellSize(at: 72))

            // Clamped before the equality check: another out-of-range write
            // at the same end changes nothing.
            let frames = view.producedFrameCount
            view.fontPointSize = 900
            #expect(view.fontPointSize == 72)
            #expect(view.producedFrameCount == frames)
        }

        @Test("a size set before install sizes the first frame")
        func sizeBeforeInstallSizesFirstFrame() throws {
            let view = GamaHostView(frame: Self.frame)
            view.fontPointSize = 28
            try view.install(app: LabelledApp())
            #expect(view.currentDrawList.size == Self.grid(view.bounds, view.cellSize))
        }

        @Test("a backing-scale change requests a redraw and changes no layout")
        func backingScaleChangeRedraws() throws {
            let view = try installedView()
            let cell = view.cellSize
            let grid = view.currentDrawList.size
            let redraws = view.redrawRequestCount

            view.viewDidChangeBackingProperties()

            #expect(view.redrawRequestCount == redraws + 1)
            #expect(view.cellSize == cell)
            #expect(view.currentDrawList.size == grid)
        }
    }
#endif

// The UIKit half. No gate builds `GamaTests` for iOS, tvOS or visionOS, so
// this block is compiled by nothing today; it records the intended contract
// for `followsDynamicType` and type-checks the moment a UIKit test build runs.
#if canImport(UIKit) && !canImport(AppKit)
    import UIKit
    import GamaAppleUI
    import Testing

    @Suite("UIKit host Dynamic Type")
    @MainActor
    struct UIKitHostDynamicTypeTests {
        @Test("following Dynamic Type applies the scaled size and restores the base size")
        func followsContentSizeCategory() {
            let view = GamaHostView(frame: CGRect(x: 0, y: 0, width: 420, height: 180))
            view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            view.followsDynamicType = true
            #expect(view.fontPointSize > 14)

            view.followsDynamicType = false
            #expect(view.fontPointSize == 14)
        }
    }
#endif

#if canImport(AppKit)
import AppKit
import GamaAppleUI
import GamaCore
import Testing

/// Pins the styled-font cache in `GamaHostView`.
///
/// Before it existed, `styledFont(for:)` built a fresh
/// `NSFont.monospacedSystemFont(ofSize:weight:)` for every text command of
/// every frame. Driven hard that intermittently produced a font CoreText
/// could not resolve, and the process aborted inside
/// `CTLineCreateWithAttributedString` with `GamaHostView.draw(_:)` on the
/// stack. Measured on branch `perf/apple-host-baseline` (whose
/// `--scenario` harness is not on this branch): 15 attempts at 500-2500
/// frames, exactly one completed; a diagnostic build whose only change was
/// a four-entry cache ran 5x2000 frames clean.
///
/// That abort is probabilistic, so reproducing it is not a test. The
/// invariant that removes it is: **the number of fonts a host constructs is
/// bounded by the number of distinct font-defining styles, not by how much
/// text it draws.** These tests assert that bound, and separately assert
/// that a cached font is the same font the uncached code would have built —
/// a cache returning a *different* font would silently change rendering.
@Suite("AppKit host styled-font cache")
@MainActor
struct AppleHostFontCacheTests {
    /// The four bold/italic combinations, plus decorations that must not
    /// affect font selection.
    private static let styles: [TextStyle] = [
        TextStyle(),
        TextStyle(attributes: [.bold]),
        TextStyle(attributes: [.italic]),
        TextStyle(attributes: [.bold, .italic]),
        TextStyle(attributes: [.dim]),
        TextStyle(attributes: [.underline]),
        TextStyle(attributes: [.inverse]),
        TextStyle(attributes: [.strikethrough]),
        TextStyle(attributes: [.bold, .underline, .inverse]),
        TextStyle(attributes: [.italic, .dim, .strikethrough]),
        TextStyle(
            foreground: Color(r: 10, g: 20, b: 30),
            background: Color(r: 40, g: 50, b: 60),
            attributes: [.bold, .italic, .underline]),
    ]

    /// Builds the font for `attributes` the way the host does, so parity can
    /// be checked against an independently constructed instance.
    private static func referenceFont(_ attributes: TextAttributes) -> NSFont {
        let weight: NSFont.Weight = attributes.contains(.bold) ? .bold : .regular
        var f = NSFont.monospacedSystemFont(ofSize: 14, weight: weight)
        if attributes.contains(.italic) {
            let d = f.fontDescriptor.withSymbolicTraits(.italic)
            f = NSFont(descriptor: d, size: f.pointSize) ?? f
        }
        return f
    }

    @Test("hosts share one immutable base font")
    func baseFontIsSharedAcrossHosts() {
        let views = (0..<32).map { _ in
            GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        }

        #expect(Set(views.map(\.baseFontIdentifier)).count == 1)
    }

    @Test("drawing text repeatedly constructs at most four fonts")
    func styledFontConstructionIsBounded() {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))

        // Far more calls than there are distinct font-defining styles: this
        // is what a few frames of a text-heavy surface look like, and what
        // the uncached path turned into one font construction each.
        for _ in 0..<200 {
            for style in Self.styles {
                _ = view.styledFont(for: style)
            }
        }

        #expect(view.styledFontConstructionCount <= 4)
        #expect(view.styledFontCacheCount <= 4)
    }

    @Test("only bold and italic add cache entries")
    func nonFontAttributesShareOneEntry() {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))

        for attributes in [
            TextAttributes(), [.dim], [.underline], [.inverse], [.strikethrough],
            [.dim, .underline, .inverse, .strikethrough],
        ] as [TextAttributes] {
            _ = view.styledFont(for: TextStyle(attributes: attributes))
        }

        #expect(view.styledFontConstructionCount == 1)
        #expect(view.styledFontCacheCount == 1)
    }

    @Test("each distinct bold/italic combination is built exactly once")
    func eachCombinationIsBuiltOnce() {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        let combinations: [TextAttributes] = [[], [.bold], [.italic], [.bold, .italic]]

        for attributes in combinations {
            _ = view.styledFont(for: TextStyle(attributes: attributes))
        }
        #expect(view.styledFontConstructionCount == 4)

        // A second pass must be served entirely from the cache.
        for attributes in combinations {
            _ = view.styledFont(for: TextStyle(attributes: attributes))
        }
        #expect(view.styledFontConstructionCount == 4)
        #expect(view.styledFontCacheCount == 4)
    }

    @Test("a cached font is the same font the uncached path would build")
    func cachedFontMatchesFreshlyBuiltFont() {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))

        for attributes in [[], [.bold], [.italic], [.bold, .italic]] as [TextAttributes] {
            let reference = Self.referenceFont(attributes)
            // Twice: the first call populates the cache, the second is served
            // from it, and both must equal the independent construction.
            for _ in 0..<2 {
                let font = view.styledFont(for: TextStyle(attributes: attributes))
                #expect(font.fontName == reference.fontName)
                #expect(font.pointSize == reference.pointSize)
                #expect(
                    font.fontDescriptor.symbolicTraits == reference.fontDescriptor.symbolicTraits)
            }
        }
    }

    @Test("caches are per view, not shared process state")
    func cachesAreConfinedToTheirHost() {
        let first = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        let second = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))

        _ = first.styledFont(for: TextStyle(attributes: [.bold]))
        #expect(first.styledFontConstructionCount == 1)
        #expect(second.styledFontConstructionCount == 0)
        #expect(second.styledFontCacheCount == 0)
    }
}
#endif

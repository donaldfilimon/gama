//  GamaHostAccessibility.swift — GamaAppleUI
//  VoiceOver adapter for GamaHostView, derived from the frame the host
//  already rendered. It publishes one accessibility element per non-blank
//  grid row; it never inspects application state and never invents a second
//  action system. Interaction semantics stay in GamaCore.

#if canImport(AppKit) || canImport(UIKit)

    #if canImport(AppKit)
        public import AppKit
    #else
        public import UIKit
    #endif

    import GamaCore
    public import GamaDraw

    extension GamaHostView {
        /// The reading-order text of the most recently rendered frame.
        ///
        /// Derived from ``currentDrawList`` and cached until the next frame
        /// replaces it, so repeated assistive-technology queries between
        /// frames cost nothing. Public because it is the testable seam:
        /// a test can assert what VoiceOver would read without driving the
        /// accessibility client itself.
        public var accessibilitySnapshot: AccessibilitySnapshot {
            if accessibilityCacheIsStale || cachedAccessibilitySnapshot == nil {
                cachedAccessibilitySnapshot = AccessibilitySnapshot.from(currentDrawList)
                cachedAccessibilityElements = nil
                accessibilityCacheIsStale = false
            }
            // The branch above assigns it; the fallback keeps the accessor
            // total rather than trapping if that ever stops being true.
            return cachedAccessibilitySnapshot ?? AccessibilitySnapshot.from(currentDrawList)
        }

        /// Converts a grid rectangle to this view's coordinate space using
        /// the measured monospaced cell size.
        func viewRect(forGrid rect: Rect) -> CGRect {
            CGRect(
                x: CGFloat(rect.minX) * accessibilityCellSize.width,
                y: CGFloat(rect.minY) * accessibilityCellSize.height,
                width: CGFloat(rect.size.width) * accessibilityCellSize.width,
                height: CGFloat(rect.size.height) * accessibilityCellSize.height)
        }

        /// Rebuilds the per-line elements if the frame changed since they
        /// were last built.
        func accessibilityLineElements() -> [GamaAccessibilityLineElement] {
            if let cached = cachedAccessibilityElements, !accessibilityCacheIsStale {
                return cached
            }
            let snapshot = accessibilitySnapshot
            let elements = snapshot.lines.map { line in
                GamaAccessibilityLineElement(line: line, host: self)
            }
            cachedAccessibilityElements = elements
            return elements
        }

        /// Called after each frame. Recomputing the snapshot on every frame
        /// would cost every host something only an assistive-technology
        /// client uses, so the change notification is armed only once a
        /// client has actually queried the view.
        func refreshAccessibilityIfObserved() {
            guard accessibilityHasBeenQueried else { return }
            let snapshot = accessibilitySnapshot
            guard snapshot != lastAnnouncedAccessibilitySnapshot else { return }
            lastAnnouncedAccessibilitySnapshot = snapshot
            #if canImport(AppKit)
                unsafe NSAccessibility.post(element: self, notification: .layoutChanged)
            #else
                unsafe UIAccessibility.post(notification: .layoutChanged, argument: nil)
            #endif
        }
    }

    // One non-blank grid row published to assistive technologies as static
    // text. It carries no behavior of its own: its label is the row's
    // characters and its frame is that row's cells scaled by the host's
    // measured cell size. The doc comment is repeated inside each branch
    // rather than hoisted above the #if, because a comment outside the
    // conditional attaches to neither declaration and the symbol graph
    // (check-doc-coverage.sh) reports it as undocumented.
    #if canImport(AppKit)
        /// One non-blank grid row published to assistive technologies as
        /// static text. It carries no behavior of its own: its label is the
        /// row's characters and its frame is that row's cells scaled by the
        /// host's measured cell size.
        @MainActor
        public final class GamaAccessibilityLineElement: NSAccessibilityElement {
            /// The grid row this element reads.
            public let line: AccessibilitySnapshot.Line

            /// Creates an element for `line`, parented to `host` and framed
            /// in the host's coordinate space.
            init(line: AccessibilitySnapshot.Line, host: GamaHostView) {
                self.line = line
                super.init()
                setAccessibilityParent(host)
                setAccessibilityRole(.staticText)
                setAccessibilityValue(line.text)
                setAccessibilityLabel(line.text)
                setAccessibilityFrameInParentSpace(host.viewRect(forGrid: line.frame))
            }
        }
    #else
        /// One non-blank grid row published to assistive technologies as
        /// static text. It carries no behavior of its own: its label is the
        /// row's characters and its frame is that row's cells scaled by the
        /// host's measured cell size.
        @MainActor
        public final class GamaAccessibilityLineElement: UIAccessibilityElement {
            /// The grid row this element reads.
            public let line: AccessibilitySnapshot.Line

            /// Creates an element for `line`, contained by `host` and framed
            /// in the host's coordinate space.
            init(line: AccessibilitySnapshot.Line, host: GamaHostView) {
                self.line = line
                super.init(accessibilityContainer: host)
                accessibilityLabel = line.text
                accessibilityTraits = .staticText
                accessibilityFrameInContainerSpace = host.viewRect(forGrid: line.frame)
            }
        }
    #endif

#endif  // canImport(AppKit) || canImport(UIKit)

//  AppKitLayoutMetrics.swift — GamaAppleUI
//  The measurements a native AppKit presentation host lays out with
//  (ADR 0017): proportional system text measured by AppKit, control sizes
//  from prototype controls, and authored cell lengths converted to points
//  with a cell size probed once from the system font. Every result is
//  rounded up to whole points, because `LayoutEngine` works in integers.

#if canImport(AppKit)

    public import AppKit
    public import GamaCore

    /// Measures Gama layout in AppKit points for ``GamaNativeHostView``.
    ///
    /// Text is measured with `NSAttributedString.boundingRect` in the
    /// system font (bold and italic through the font's symbolic traits) and
    /// cached by string, style, and wrap width. Controls are sized from a
    /// reusable prototype control's `fittingSize`. One authored cell is
    /// ``cellSize`` points: the rounded-up size of `"M"` in the system font.
    ///
    /// The ``metrics`` closures call back into this object and assume the
    /// main actor, which is where every AppKit host pumps its frames.
    @MainActor
    public final class AppKitLayoutMetrics {
        /// Points per authored cell on each axis, probed once from the
        /// system font and rounded up to whole points.
        public let cellSize: CGSize

        /// Horizontal points an `NSTextField` label cell adds around its
        /// text (its line-fragment padding, two points per side). Every
        /// measured text width includes it, so a label given its measured
        /// frame never clips or wraps its last word.
        public static let labelPadding: CGFloat = 4

        /// How many text measurements missed the cache and reached AppKit.
        /// Package-only, so a test can prove the cache is consulted.
        package private(set) var textMeasurementCount = 0

        private let fontSize = NSFont.systemFontSize
        private var fontCache: [TextAttributes: NSFont] = [:]
        private var textCache: [TextKey: Size] = [:]
        private lazy var pushPrototype = NSButton(title: "", target: nil, action: nil)
        private lazy var checkboxPrototype = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        private lazy var fieldPrototype = NSTextField(string: "")
        private lazy var progressPrototype: NSProgressIndicator = {
            let indicator = NSProgressIndicator()
            indicator.style = .bar
            indicator.isIndeterminate = false
            return indicator
        }()

        private struct TextKey: Hashable {
            var text: String
            var attributes: TextAttributes
            var width: Int?
        }

        /// Probes the cell size from the system font.
        public init() {
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let probe = NSAttributedString(string: "M", attributes: [.font: font]).size()
            cellSize = CGSize(width: max(1, probe.width.rounded(.up)), height: max(1, probe.height.rounded(.up)))
        }

        /// A ``LayoutMetrics`` value measuring through this object. Its
        /// closures must be called on the main actor.
        public var metrics: LayoutMetrics {
            let columnPoints = Int(cellSize.width)
            let rowPoints = Int(cellSize.height)
            return LayoutMetrics(
                textSize: { [self] text, style, width in
                    MainActor.assumeIsolated { self.textSize(text, style: style, width: width) }
                },
                units: { cells, axis in
                    cells * (axis == .horizontal ? columnPoints : rowPoints)
                },
                dividerThickness: max(1, rowPoints / 2),
                controlSize: { _, _ in nil },
                descriptorSize: { [self] descriptor, proposal in
                    MainActor.assumeIsolated { self.controlSize(for: descriptor, proposal: proposal) }
                }
            )
        }

        /// The size of `text` drawn in `style`, wrapped to `width` points
        /// when given, rounded up to whole points. Text AppKit cannot
        /// measure (empty, or a non-finite or empty bounding box) falls back
        /// to ``LayoutMetrics/cell`` scaled by ``cellSize``.
        public func textSize(_ text: String, style: TextStyle, width: Int?) -> Size {
            let key = TextKey(text: text, attributes: style.attributes.intersection([.bold, .italic]), width: width)
            if let cached = textCache[key] { return cached }
            textMeasurementCount += 1
            let measured = measure(text, attributes: key.attributes, width: width)
            textCache[key] = measured
            return measured
        }

        /// The fitted size of the platform control `descriptor` maps to,
        /// rounded up to whole points, or `nil` for a button whose label is
        /// not plain text (its label subtree is measured instead).
        public func controlSize(for descriptor: ControlDescriptor, proposal: ProposedSize) -> Size? {
            switch descriptor {
            case .button(let title, _):
                guard let title else { return nil }
                pushPrototype.title = title
                return rounded(pushPrototype.fittingSize)
            case .toggle(let title, _, _):
                checkboxPrototype.title = title
                return rounded(checkboxPrototype.fittingSize)
            case .textField(let placeholder, let text, _, _):
                fieldPrototype.stringValue = text
                fieldPrototype.placeholderString = placeholder
                let fitted = rounded(fieldPrototype.fittingSize)
                let shown = textSize(text.isEmpty ? placeholder : text, style: .plain, width: nil)
                // A field is never narrower than twelve cells, so an empty
                // field still has room to type into.
                let minimum = 12 * Int(cellSize.width)
                return Size(width: max(fitted.width, shown.width + 8, minimum), height: max(fitted.height, shown.height))
            case .progress:
                let fitted = rounded(progressPrototype.fittingSize)
                // A bar has no intrinsic width; give it the cell backend's
                // default of twenty cells.
                return Size(width: max(fitted.width, 20 * Int(cellSize.width)), height: max(fitted.height, 1))
            }
        }

        private func measure(_ text: String, attributes: TextAttributes, width: Int?) -> Size {
            let cellFallback: Size = {
                let cells = LayoutMetrics.cell.textSize(
                    text, .plain, width.map { max(0, $0 / max(1, Int(cellSize.width))) })
                return Size(width: cells.width * Int(cellSize.width), height: cells.height * Int(cellSize.height))
            }()
            guard !text.isEmpty else { return cellFallback }
            let string = NSAttributedString(string: text, attributes: [.font: font(for: attributes)])
            let bound = width.map { CGFloat(max(1, $0)) - Self.labelPadding } ?? .greatestFiniteMagnitude
            let rect = string.boundingRect(
                with: NSSize(width: bound, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            guard bound > 0, rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
                return cellFallback
            }
            var size = rounded(CGSize(width: rect.width + Self.labelPadding, height: rect.height))
            if let width { size.width = min(size.width, max(0, width)) }
            return size
        }

        /// The system font for `attributes` (bold and italic only), built
        /// once per combination.
        package func font(for attributes: TextAttributes) -> NSFont {
            let key = attributes.intersection([.bold, .italic])
            if let cached = fontCache[key] { return cached }
            var font = NSFont.systemFont(ofSize: fontSize, weight: key.contains(.bold) ? .bold : .regular)
            if key.contains(.italic) {
                let descriptor = font.fontDescriptor.withSymbolicTraits(
                    key.contains(.bold) ? [.italic, .bold] : .italic)
                font = NSFont(descriptor: descriptor, size: fontSize) ?? font
            }
            fontCache[key] = font
            return font
        }

        private func rounded(_ size: CGSize) -> Size {
            Size(
                width: size.width.isFinite ? Int(max(0, size.width).rounded(.up)) : 0,
                height: size.height.isFinite ? Int(max(0, size.height).rounded(.up)) : 0)
        }
    }

#endif  // canImport(AppKit)

#if canImport(AppKit)
    import AppKit
    import GamaAppleUI
    import GamaCore
    import Testing

    @Suite("AppKit layout metrics")
    @MainActor
    struct AppKitLayoutMetricsTests {
        @Test("the cell probe is positive and matches the system font")
        func cellProbe() {
            let measurer = AppKitLayoutMetrics()
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let probe = NSAttributedString(string: "M", attributes: [.font: font]).size()
            #expect(measurer.cellSize.width > 0 && measurer.cellSize.height > 0)
            #expect(measurer.cellSize.width == probe.width.rounded(.up))
            #expect(measurer.cellSize.height == probe.height.rounded(.up))
            let metrics = measurer.metrics
            #expect(metrics.units(3, .horizontal) == 3 * Int(measurer.cellSize.width))
            #expect(metrics.units(2, .vertical) == 2 * Int(measurer.cellSize.height))
        }

        @Test("text is proportional: iiii is narrower than WWWW")
        func proportional() {
            let metrics = AppKitLayoutMetrics().metrics
            let narrow = metrics.textSize("iiii", .plain, nil)
            let wide = metrics.textSize("WWWW", .plain, nil)
            #expect(narrow.width > 0)
            #expect(narrow.width < wide.width)
            #expect(narrow.height == wide.height)
        }

        @Test("wrapping at a maximum width increases height")
        func wraps() {
            let metrics = AppKitLayoutMetrics().metrics
            let text = "The quick brown fox jumps over the lazy dog again and again"
            let unwrapped = metrics.textSize(text, .plain, nil)
            let wrapped = metrics.textSize(text, .plain, 80)
            #expect(wrapped.height > unwrapped.height)
            #expect(wrapped.width <= 80)
        }

        @Test("results round AppKit's measurement up to whole points")
        func roundsUp() {
            let measurer = AppKitLayoutMetrics()
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let raw = NSAttributedString(string: "Gama", attributes: [.font: font])
                .boundingRect(
                    with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
            let size = measurer.metrics.textSize("Gama", .plain, nil)
            #expect(CGFloat(size.width) == raw.width.rounded(.up))
            #expect(CGFloat(size.height) == raw.height.rounded(.up))
        }

        @Test("bold text measures wider than plain text")
        func bold() {
            let metrics = AppKitLayoutMetrics().metrics
            let plain = metrics.textSize("Measure me", .plain, nil)
            let bold = metrics.textSize("Measure me", TextStyle(attributes: [.bold]), nil)
            #expect(bold.width > plain.width)
        }

        @Test("the cache returns identical values without measuring again")
        func cache() {
            let measurer = AppKitLayoutMetrics()
            let metrics = measurer.metrics
            let first = metrics.textSize("cached", .plain, 200)
            let count = measurer.textMeasurementCount
            let second = metrics.textSize("cached", .plain, 200)
            #expect(first == second)
            #expect(measurer.textMeasurementCount == count)
            _ = metrics.textSize("cached", .plain, 100)
            #expect(measurer.textMeasurementCount == count + 1)
        }

        @Test("control sizes are positive for every mapped control")
        func controlSizes() throws {
            let metrics = AppKitLayoutMetrics().metrics
            let proposal = ProposedSize(width: nil, height: nil)
            let descriptors: [ControlDescriptor] = [
                .button(title: "Push", isEnabled: true),
                .toggle(title: "Check", isOn: true, isEnabled: true),
                .textField(placeholder: "Name", text: "", isEnabled: true, setText: { _ in }),
                .progress(fraction: 0.5, label: nil),
            ]
            for descriptor in descriptors {
                let size = try #require(metrics.descriptorSize(descriptor, proposal))
                #expect(size.width > 0 && size.height > 0)
            }
            // A composite button label measures its own children.
            #expect(metrics.descriptorSize(.button(title: nil, isEnabled: true), proposal) == nil)
        }

        @Test("text AppKit cannot measure falls back to cell metrics scaled by the cell size")
        func fallback() {
            let measurer = AppKitLayoutMetrics()
            let empty = measurer.metrics.textSize("", .plain, nil)
            let cells = LayoutMetrics.cell.textSize("", .plain, nil)
            #expect(empty.width == cells.width * Int(measurer.cellSize.width))
            #expect(empty.height == cells.height * Int(measurer.cellSize.height))
        }
    }
#endif

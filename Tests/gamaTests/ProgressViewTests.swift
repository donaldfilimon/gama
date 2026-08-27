import GamaCore
import Testing

/// Renders a `ProgressView` and extracts its `.text` payload, failing the
/// test (rather than crashing) if the primitive ever compiles to anything
/// else.
private func renderedText(_ view: ProgressView) -> String {
    guard case .text(let text, _) = view.render(in: BuildContext()) else {
        Issue.record("ProgressView did not render text")
        return ""
    }
    return text
}

/// Covers the "scale-aware ProgressView" backlog item: the bar used to
/// quantize to whole cells only (`Int(fraction * 20 + 0.5)`), so 0.99 and
/// 1.0 filled the same 20th cell and rendered identically. These tests
/// pin the eighth-cell sub-resolution fix plus the clamping/degenerate-
/// input guarantees layered onto it.
@Suite("ProgressView scale awareness")
struct ProgressViewTests {
    @Test("0.0 renders fully empty with no partial glyph")
    func zeroIsEmpty() {
        let text = renderedText(ProgressView(value: 0, total: 1))
        #expect(text == "[░░░░░░░░░░░░░░░░░░░░] 0%")
    }

    @Test("1.0 renders fully solid with no partial glyph")
    func oneIsFull() {
        let text = renderedText(ProgressView(value: 1, total: 1))
        #expect(text == "[████████████████████] 100%")
    }

    @Test("0.99 is visibly distinct from 1.0 at the default width")
    func almostFullIsNotFull() {
        let text = renderedText(ProgressView(value: 0.99, total: 1))
        #expect(text == "[███████████████████▊] 99%")
        #expect(text != renderedText(ProgressView(value: 1, total: 1)))
    }

    @Test("a fraction within one float ulp of 1 still never reads as full")
    func nearOneNeverRoundsUpToFull() {
        // 0.999999 * 160 eighths = 159.99984, which rounds to 160 (the
        // full width) under plain rounding. The cap must catch this or
        // floating-point rounding alone would reintroduce the bug this
        // slice fixes.
        let text = renderedText(ProgressView(value: 0.999999, total: 1))
        #expect(text == "[███████████████████▉] 99%")
    }

    @Test("sub-cell fraction 1/8 renders a half-block boundary glyph")
    func subCellStep() {
        let text = renderedText(ProgressView(value: 1, total: 8, label: "Load"))
        #expect(text == "Load [██▌░░░░░░░░░░░░░░░░░] 13%")
    }

    @Test("NaN clamps to the empty end")
    func nanClampsToZero() {
        let text = renderedText(ProgressView(value: .nan, total: 1))
        #expect(text == "[░░░░░░░░░░░░░░░░░░░░] 0%")
    }

    @Test("+infinity clamps to the full end")
    func positiveInfinityClampsToFull() {
        let text = renderedText(ProgressView(value: .infinity, total: 1))
        #expect(text == "[████████████████████] 100%")
    }

    @Test("-infinity clamps to the empty end")
    func negativeInfinityClampsToZero() {
        let text = renderedText(ProgressView(value: -.infinity, total: 1))
        #expect(text == "[░░░░░░░░░░░░░░░░░░░░] 0%")
    }

    @Test("a negative value clamps to the empty end")
    func negativeValueClampsToZero() {
        let text = renderedText(ProgressView(value: -5, total: 1))
        #expect(text == "[░░░░░░░░░░░░░░░░░░░░] 0%")
    }

    @Test("a value past total clamps to the full end")
    func overTotalClampsToFull() {
        let text = renderedText(ProgressView(value: 5, total: 1))
        #expect(text == "[████████████████████] 100%")
    }

    @Test("a non-positive total renders empty regardless of value")
    func nonPositiveTotalRendersEmpty() {
        #expect(renderedText(ProgressView(value: 1, total: 0)) == "[░░░░░░░░░░░░░░░░░░░░] 0%")
        #expect(renderedText(ProgressView(value: 1, total: -1)) == "[░░░░░░░░░░░░░░░░░░░░] 0%")
    }

    @Test("width 0 degrades to an empty bracket without crashing")
    func zeroWidthDoesNotCrash() {
        let text = renderedText(ProgressView(value: 0.5, total: 1, width: 0))
        #expect(text == "[] 50%")
    }

    @Test("negative width degrades to an empty bracket without crashing")
    func negativeWidthDoesNotCrash() {
        let text = renderedText(ProgressView(value: 0.5, total: 1, width: -5))
        #expect(text == "[] 50%")
    }

    @Test("width 1 still resolves sub-cell progress instead of an all-or-nothing cell")
    func widthOneStillResolvesSubCellSteps() {
        #expect(renderedText(ProgressView(value: 0.5, total: 1, width: 1)) == "[▌] 50%")
        #expect(renderedText(ProgressView(value: 1, total: 1, width: 1)) == "[█] 100%")
        // Even squeezed into a single cell, 0.99 must not collapse onto
        // the same glyph as 1.0 — this is the narrowest case the "not
        // full" guarantee has to hold for.
        let almostFull = renderedText(ProgressView(value: 0.99, total: 1, width: 1))
        #expect(almostFull == "[▉] 99%")
        #expect(almostFull != renderedText(ProgressView(value: 1, total: 1, width: 1)))
    }
}

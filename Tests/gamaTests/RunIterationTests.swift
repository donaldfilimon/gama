//  RunIterationTests.swift — run-loop iteration.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

@Suite("Run iteration")
struct RunIterationTests {
    @Test("forEachRun merges identical styles")
    func forEachRunMergesIdenticalStyles() {
        var buf = CellBuffer(size: Size(width: 6, height: 1))
        buf.clearBack()
        let red = TextStyle(foreground: .red)
        buf.putText("ab", at: Point(x: 0, y: 0), style: red, maxWidth: 6)
        buf.putText("cd", at: Point(x: 2, y: 0), style: red, maxWidth: 4)
        var runs: [(String, TextStyle)] = []
        buf.forEachRun { _, _, _, text, style in runs.append((text, style)) }
        #expect(runs.count == 2)
        #expect(runs[0].0 == "abcd")
        #expect(runs[0].1.foreground == .red)
        #expect(runs[1].0 == "  ")
    }

    @Test("forEachRun splits on style change")
    func forEachRunSplitsOnStyleChange() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.clearBack()
        buf.putText("ab", at: Point(x: 0, y: 0), style: TextStyle(foreground: .red), maxWidth: 4)
        buf.putText("cd", at: Point(x: 2, y: 0), style: TextStyle(foreground: .blue), maxWidth: 2)
        var runs: [String] = []
        buf.forEachRun { _, _, _, text, _ in runs.append(text) }
        #expect(runs == ["ab", "cd"])
    }
}

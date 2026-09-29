// Swift/C++ interop bridge (Swift 6.4 + CxxStdlib).

import CGamaQt
import CxxStdlib
import Foundation

/// Retains log lines for C++ → Swift callbacks (`runWithLogger`).
///
/// Marked `@unchecked Sendable` because the C++ thunk may call back on the
/// thread that invoked `gama.runWithLogger`; callers must keep the box alive
/// for the duration of that call (stack / local retention is enough).
final class GamaLogBox: @unchecked Sendable {
    private(set) var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }
}

private let gamaSwiftLogThunk: gama.SwiftLog = { line, context in
    let text = String(line)
    guard let context else {
        print("[cxx→swift]", text)
        return
    }
    Unmanaged<GamaLogBox>.fromOpaque(context).takeUnretainedValue().append(text)
}

/// Swift façade over the `gama` C++ API in `CGamaQt`.
///
/// **Qt application:** `ensureApplication()` creates/reuses a process-wide
/// `QApplication`. Safe to call repeatedly from AppKit/SwiftUI.
///
/// **Embedded panel:** at most one panel exists at a time. Ownership:
/// 1. `createPanelNSView()` → CGamaQt owns the `QWidget`; returns an
///    unretained Cocoa `NSView*` (`QWidget::winId()`).
/// 2. Host (e.g. `QtPanelView`) adds that view as a subview but must **not**
///    release it.
/// 3. `releasePanel()` destroys the widget; call from `dismantleNSView`.
///
/// **Event pump:** while Cocoa owns the run loop, call `processEvents()`
/// periodically (and optionally from panel `updateNSView`).
enum GamaQt {
    static func version() -> String {
        String(gama.qtVersion())
    }

    static func greet(name: String) -> String {
        String(gama.greet(std.string(name)))
    }

    static func runLegacyBrowser() {
        gama.runBrowser()
    }

    /// Runs the C++ logger demo; returns collected lines (also writes via thunk).
    @discardableResult
    static func runWithLogger(into box: GamaLogBox? = nil) -> [String] {
        let box = box ?? GamaLogBox()
        let context = Unmanaged.passUnretained(box).toOpaque()
        gama.runWithLogger(gamaSwiftLogThunk, context)
        return box.lines
    }

    static func ensureApplication() {
        gama.ensureQtApplication()
    }

    static func processEvents() {
        gama.processQtEvents()
    }

    /// Returns an unretained `NSView*` for the shared embed panel, or `nil`.
    /// Pair with `releasePanel()` when the host tears down.
    static func createPanelNSView() -> UnsafeMutableRawPointer? {
        gama.createQtPanelNSView()
    }

    /// Destroys the shared embed panel. Idempotent from the C++ side.
    static func releasePanel() {
        gama.releaseQtPanel()
    }

    static func setPanelStatus(_ text: String) {
        gama.setQtPanelStatus(std.string(text))
    }
}

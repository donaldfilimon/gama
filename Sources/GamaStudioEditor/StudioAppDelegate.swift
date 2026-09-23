//  StudioAppDelegate.swift — GamaStudioEditor
//
//  The app-lifecycle half of hosting Gama Studio: without an
//  `NSApplicationDelegate`, AppKit's default is to keep the process alive
//  after its last window closes, leaving a windowless `gama-studio` running.
//  This lives in the library (not `Sources/gama-studio/main.swift`) so
//  `GamaStudioEditorTests` can exercise it directly — an executable target
//  can't be imported by a test target.

#if canImport(AppKit)

public import AppKit

/// Terminates `gama-studio` when its one window closes, instead of AppKit's
/// default of leaving a windowless process running.
///
/// The executable holds one instance strongly for the process's lifetime
/// (`NSApplication.delegate` itself is a weak reference), and sets it with
/// `NSApplication.shared.delegate = appDelegate` before the window is shown.
@MainActor
public final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Creates the studio's main window with the style mask `gama-studio`
    /// uses and `isReleasedWhenClosed = false`.
    ///
    /// A top-level `let window` in `main.swift` holds this strongly for the
    /// whole process, so AppKit's default `isReleasedWhenClosed = true`
    /// would release it a second time when the window closes — this factory
    /// is the one place that decision is made, so it can't drift from the
    /// executable that relies on it.
    public static func makeMainWindow(contentRect: NSRect, title: String = "Gama Studio") -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }
}
#endif

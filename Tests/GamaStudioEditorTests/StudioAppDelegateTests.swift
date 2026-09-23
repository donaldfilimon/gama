//  StudioAppDelegateTests.swift — GamaStudioEditorTests
//
//  Pins the process-lifecycle fix directly: without these, `gama-studio`
//  would leave a windowless process running after its last window closes
//  (AppKit's default), and its window would double-release under
//  `isReleasedWhenClosed`'s own default while a global held it strongly.

#if canImport(AppKit)

import AppKit
import GamaStudioEditor
import Testing

@MainActor
@Suite("StudioAppDelegate")
struct StudioAppDelegateTests {
    @Test func terminatesAfterTheLastWindowCloses() {
        let delegate = StudioAppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @Test func mainWindowIsNotReleasedWhenClosed() {
        let window = StudioAppDelegate.makeMainWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480))
        defer { window.close() }
        #expect(window.isReleasedWhenClosed == false)
        #expect(window.title == "Gama Studio")
    }
}
#endif

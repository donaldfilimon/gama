//  main.swift — gama-studio
//
//  Dependency-spike stub: opens a native AppKit window hosting
//  GamaStudioEditor's StudioApp through gama's GamaHostView. `--smoke`
//  skips the event loop and asserts a real frame was produced instead.
//
//  Top-level code in main.swift is implicitly @MainActor-isolated, which is
//  what lets this call straight into AppKit and GamaAppleUI's @MainActor
//  GamaHostView without extra isolation ceremony.

import AppKit
import Foundation
import GamaCore
import GamaDraw
import GamaAppleUI
import GamaStudioEditor

let isSmoke = CommandLine.arguments.contains("--smoke")

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Minimal app menu so Cmd+Q works once the window is on screen.
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(
    withTitle: "Quit Gama Studio",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
)
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

let windowRect = NSRect(x: 0, y: 0, width: 1280, height: 800)
let window = NSWindow(
    contentRect: windowRect,
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered,
    defer: false
)
window.title = "Gama Studio"

let hostView = GamaHostView(frame: windowRect)
hostView.autoresizingMask = [.width, .height]
window.contentView = hostView

do {
    try hostView.install(app: StudioApp())
} catch {
    FileHandle.standardError.write(Data("gama-studio: install failed: \(error)\n".utf8))
    exit(1)
}

if isSmoke {
    app.finishLaunching()
    hostView.invalidate()
    let count = hostView.currentDrawList.commands.count
    if count > 0 {
        print("gama-studio smoke: OK")
        exit(0)
    } else {
        print("gama-studio smoke: FAILED (0 draw commands)")
        exit(1)
    }
} else {
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}

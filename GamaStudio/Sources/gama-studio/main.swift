//  main.swift — gama-studio
//
//  Opens a native AppKit window hosting GamaStudioEditor's StudioApp through
//  gama's GamaHostView, with a RealityKit ARView attached to the app's
//  viewport region. `--smoke` skips the event loop and asserts a real frame
//  was produced and the viewport placed; `--snapshot <png>` renders the
//  ARView once to a PNG for visual evidence. `--open <usda>` starts from a
//  file instead of the sample scene, and `--export <usda>` writes the document
//  (opened or sample) and exits without building any UI (ADR 0005).
//
//  Top-level code in main.swift is implicitly @MainActor-isolated, which is
//  what lets this call straight into AppKit and GamaAppleUI's @MainActor
//  GamaHostView without extra isolation ceremony.

import AppKit
import Foundation
import GamaCore
import GamaDraw
import GamaAppleUI
import GamaAuthoring
import GamaReality
import GamaStudioEditor
import RealityKit

let arguments = CommandLine.arguments
let isSmoke = arguments.contains("--smoke")
/// The argument after `flag`; exits 2 when the flag is present without one.
func path(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    let next = arguments.index(after: index)
    guard next < arguments.endIndex, !arguments[next].hasPrefix("--") else {
        FileHandle.standardError.write(Data("gama-studio: \(flag) needs a path\n".utf8))
        exit(2)
    }
    return arguments[next]
}
// Every option is known, and the modes exclude each other: a mistyped flag
// must not fall through to launching the GUI, which would hang a script.
let valueFlags: Set<String> = ["--snapshot", "--open", "--export"]
var skipNext = false
for argument in arguments.dropFirst() {
    if skipNext { skipNext = false; continue }
    guard argument.hasPrefix("--") else { continue }
    guard valueFlags.contains(argument) || argument == "--smoke" else {
        FileHandle.standardError.write(Data("gama-studio: unknown option \(argument)\n".utf8))
        exit(2)
    }
    skipNext = valueFlags.contains(argument)
}
let modes = ["--smoke", "--snapshot", "--export"].filter(arguments.contains)
if modes.count > 1 {
    FileHandle.standardError.write(Data("gama-studio: \(modes.joined(separator: " and ")) cannot be combined\n".utf8))
    exit(2)
}
let snapshotPath = path(after: "--snapshot")
let openURL = path(after: "--open").map { URL(fileURLWithPath: $0) }
let exportURL = path(after: "--export").map { URL(fileURLWithPath: $0) }

var document = StudioModel.sampleScene()
if let openURL {
    do {
        document = try StudioDocumentIO.read(from: openURL)
    } catch {
        FileHandle.standardError.write(Data("gama-studio: cannot open \(openURL.path): \(StudioDocumentIO.describe(error))\n".utf8))
        exit(1)
    }
}
// Headless: no NSApplication, window, or viewport is ever built.
if let exportURL {
    do {
        try StudioDocumentIO.write(document, to: exportURL)
        print("gama-studio: wrote \(exportURL.path) (\(document.count) entities)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("gama-studio: cannot write \(exportURL.path): \(StudioDocumentIO.describe(error))\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
// --smoke runs headlessly under the gate and should never put an icon in
// the Dock; the interactive and --snapshot paths keep the normal policy
// (--snapshot needs an on-screen window to render into).
app.setActivationPolicy(isSmoke ? .prohibited : .regular)

// Without an app delegate, AppKit's default is to keep the process alive
// after its last window closes, leaving a windowless `gama-studio` behind.
// `appDelegate` is a top-level `let`, so it lives for the whole process;
// `NSApplication.delegate` itself holds its delegate only weakly.
let appDelegate = StudioAppDelegate()
app.delegate = appDelegate

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
mainMenu.addItem(appDelegate.makeFileMenuItem())
app.mainMenu = mainMenu

let windowRect = NSRect(x: 0, y: 0, width: 1280, height: 800)
let window = StudioAppDelegate.makeMainWindow(contentRect: windowRect)

let hostView = GamaHostView(frame: windowRect)
hostView.autoresizingMask = [.width, .height]
window.contentView = hostView

// The model, host, and viewport are top-level globals, so they live for the
// whole process; the viewport's click handler relies on that.
let model = StudioModel(document: document)
// Built before the app is installed so the viewport buttons ("Frame",
// "Look through") can reach it; it depends on the host only through this
// redraw closure.
let viewport = ViewportController(model: model, onSelectionChange: { hostView.invalidate() })
let viewportActions = ViewportActions(
    frameSelection: { viewport.frameSelection() },
    lookThrough: { viewport.lookThrough($0) }
)
do {
    try hostView.install(app: StudioApp(model: model, viewport: viewportActions))
} catch {
    FileHandle.standardError.write(Data("gama-studio: install failed: \(error)\n".utf8))
    exit(1)
}
hostView.attach(viewport.arView, to: StudioApp.viewportRegion)
// After the viewport, so the window title follows edits once the fallback
// light already has.
appDelegate.attach(model: model, window: window, url: openURL, redraw: { hostView.invalidate() })

/// Whether `rep` has more than one distinct colour across a coarse grid of
/// samples: a blank or single-colour render fails this.
func imageVaries(_ rep: NSBitmapImageRep) -> (varies: Bool, distinct: Int) {
    var seen = Set<[Int]>()
    let steps = 8
    for i in 0..<steps {
        for j in 0..<steps {
            let x = (rep.pixelsWide - 1) * i / (steps - 1)
            let y = (rep.pixelsHigh - 1) * j / (steps - 1)
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            seen.insert([color.redComponent, color.greenComponent, color.blueComponent].map { Int($0 * 255) })
        }
    }
    return (seen.count > 1, seen.count)
}

if isSmoke {
    app.finishLaunching()
    hostView.invalidate()
    var failures: [String] = []
    if hostView.currentDrawList.commands.isEmpty { failures.append("0 draw commands") }
    if viewport.arView.superview !== hostView { failures.append("ARView is not a subview of the host") }
    if viewport.arView.isHidden { failures.append("ARView is hidden") }
    let frame = viewport.arView.frame
    if !(frame.width > 0 && frame.height > 0) { failures.append("ARView frame is empty: \(frame)") }
    if model.bridge.count != model.session.document.count {
        failures.append("bridge holds \(model.bridge.count) entities, document \(model.session.document.count)")
    }
    if model.bridge.count < 4 { failures.append("bridge holds \(model.bridge.count) entities, expected >= 4") }
    if failures.isEmpty {
        print("gama-studio smoke: OK (viewport \(Int(frame.width))x\(Int(frame.height)) at \(Int(frame.minX)),\(Int(frame.minY)); \(model.bridge.count) entities)")
        exit(0)
    } else {
        print("gama-studio smoke: FAILED (\(failures.joined(separator: "; ")))")
        exit(1)
    }
} else if let snapshotPath {
    app.finishLaunching()
    window.center()
    window.orderFront(nil)
    hostView.invalidate()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
    var finished = false
    viewport.arView.snapshot(saveToHDR: false) { image in
        MainActor.assumeIsolated {
            defer { finished = true }
            guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                print("gama-studio snapshot: FAILED (no image)")
                exit(1)
            }
            do {
                try png.write(to: URL(fileURLWithPath: snapshotPath))
            } catch {
                print("gama-studio snapshot: FAILED (write: \(error))")
                exit(1)
            }
            let (varies, distinct) = imageVaries(rep)
            print("gama-studio snapshot: wrote \(snapshotPath) (\(rep.pixelsWide)x\(rep.pixelsHigh), \(distinct) distinct sampled colours, \(varies ? "non-blank" : "BLANK"))")
            exit(varies ? 0 : 1)
        }
    }
    let deadline = Date(timeIntervalSinceNow: 10)
    while !finished, Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    print("gama-studio snapshot: FAILED (timed out waiting for the snapshot)")
    exit(1)
} else {
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}

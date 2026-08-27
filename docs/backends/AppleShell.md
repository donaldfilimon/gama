# macOS application shell (GamaAppleShell)

Status: implemented and locally proven by the pinned Apple build and six
offscreen AppKit tests. Hosted evidence is recorded by the delivery pull
request's complete acceptance matrix; this guide does not substitute source
presence for that proof.

`GamaAppleShell` is the opt-in owner for a complete macOS application. It is
separate from `GamaAppleUI`, whose `GamaHostView` remains available to custom
AppKit/UIKit hosts.

## Launch

Declare one explicit primary scene, then start the shell on the main actor:

```swift
import GamaAppleShell
import GamaCore

private let documents = WindowGroupKey<Int>("documents")

struct DocumentApp: App {
    var scenes: some Scene {
        WindowGroup(
            "Document",
            key: documents,
            role: .primary,
            initialValue: 1
        ) { value in
            Text("Document \(value)")
        }

        Window("Inspector", id: "inspector") {
            Text("Inspector")
        }
    }
}

try GamaShell.run(DocumentApp.self)
```

The graph is compiled and validated before `NSApplication` starts. The shell
opens every `openAtLaunch` declaration in source order. Reopening a singleton
or the same typed group payload focuses its existing `WindowInstanceID`;
another payload creates an independent controller, frame host, focus/action
state, subscriptions, dirty state, and draw list.

Window actions are enqueued in a per-shell, main-actor-confined store and
drained after Gama event dispatch. There is no process-global scene or window
registry.

## Lifecycle and close behavior

AppKit activation, focus, close, and termination callbacks become portable
`LifecycleEvent` values. Application events reach the one shared app handler
once per callback. Window events include both `SceneID` and
`WindowInstanceID` and are delivered only to the addressed live host.

Close is deliberately non-vetoable in this version. The shell emits
`windowCloseRequested`, cancels that host's subscriptions, closes the native
window, then emits `windowDidClose`. Closing the final window leaves the
application resident. A Dock reopen with no live windows recreates the primary
scene from its initial payload. Only explicit Quit or Command-Q terminates and
emits `willTerminate`.

## Demo and supplemental smoke

Run the unbundled demonstration:

```bash
unset TOOLCHAINS
swiftly run swift run gama-apple-demo
```

The automated suite proves controller and delegate behavior without entering
the global event loop. The supplemental manual smoke is:

1. Open the current payload again and confirm the existing window focuses.
2. Open a different payload and confirm an independent window appears.
3. Open the auxiliary Inspector singleton twice and confirm only one exists.
4. Close every window and confirm the process remains in the Dock.
5. Click the Dock icon and confirm the primary payload reopens.
6. Press Command-Q and confirm the process terminates.

This manual path is not packaging proof. A `.app` bundle, signing,
notarization, placement restoration, close veto, UIKit scene delegates, and a
Windows GUI remain separate work.

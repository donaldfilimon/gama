# ADR 0014: Sweeping and adopting on discarded scene sessions

Status: Accepted (2026-09-23)

## Context

ADR 0013 sweeps orphaned Untitled recovery files only at a window's first
appearance. Donald asked on 2026-09-23 to also sweep when the system discards
scene sessions, and chose to:

- keep the 7-day grace period;
- let windows adopt discarded windows' recovery files.

He chose adoption while a suspected iPhone gap was unmeasured, and kept it
after the measurement below showed there was no gap on iPhone.

**Measured first (iPhone 17 simulator, iOS 27.2).** Swiping the app away in
the app switcher did not discard its scene session. After relaunching, UIKit's
log showed the same `persistentIdentifier` (`7EC8BB16-…`), and the unsaved
Untitled edit (`Light 2`) came back from the same recovery file. The same held
for a second edit (`Camera 2`) after the build below. So ADR 0012's recovery
already survives an app-switcher kill on iPhone. Adoption matters where
windows really close for good: iPad and visionOS.

## Decision

1. **A discard sweeps, with the grace period.** `StudioApplicationDelegate`,
   installed with `@UIApplicationDelegateAdaptor`, forwards
   `application(_:didDiscardSceneSessions:)` to `sessionsDiscarded(_:)`,
   which:
   - drops those keys from this process's window registry
     (`RecoveryWindows.activeKeys`);
   - runs the unchanged ADR 0013 sweep with the live set from
     `UntitledRecovery.liveKeys(open:discarded:active:)`: open sessions,
     minus the discarded ones, plus this process's windows. A discarded
     window's file is therefore no longer protected, but it is still deleted
     only after 7 unmodified days;
   - posts `RecoveryWindows.sessionsDiscarded`.
2. **Adoption.** A window with no recovery file of its own takes over the
   newest adoptable orphan by renaming it to its own key
   (`UntitledRecovery.newestAdoptable` and `adopt`), then restores it as
   ADR 0012 does: Untitled, with unsaved changes. Adoptable means:
   - a `<key>.usda` whose key is not live;
   - modified within the grace period.

   Set-aside files, anything older (left for the sweep), and foreign files
   are never adopted. It happens:
   - at first appearance, before restoring;
   - after a discard, through the notification, but only into a window
     nobody has touched: Untitled, revision 0, nothing restored or adopted.
     That covers a discard delivered after the first window appeared.
3. **Who may adopt.** Windows named by their scene session always may. A
   window with an explicit `--recovery-key` (the gate's, or a developer's)
   adopts only with `--adopt-orphans`, so leftovers from the gate or from
   development are never picked up by accident.
4. **Gate.** Two more launches per simulator:
   - **adopt:** plant an orphan holding `everything.usda`, then require that
     it was adopted as unsaved Untitled changes equal to that file, that it
     is gone from its old name, and that the window has its own recovery
     file;
   - **discard:** with no real sessions, the smoke discards two made-up
     keys: one registered as a window of this run, with a file past the
     grace period, and one never live, with a fresh file. Only the old file
     may go, the key must leave the registry, and the window's own file must
     stay.

## Consequences

- **Visible behavior.** On iPad and visionOS, a *new* window opened within
  7 days of closing a window with unsaved Untitled changes starts with those
  changes, marked unsaved, and gets the Untitled prompt. They are offered
  rather than lost. That is the accepted trade.
- **macOS unit tests** cover:
  - the live set: discarded removed, this process's windows kept;
  - adoptable choice: newest young orphan only;
  - adopting: renames byte for byte, then restores as unsaved; refuses when
    the window has a file; harmless when the orphan is gone.

  The earlier sweep tests pass unchanged after the parsing moved into one
  shared scanner.
- **Mutation checks, each failing as intended:**
  - without the adopt call, the adopt launch fails on five lines;
  - without the sweep in `sessionsDiscarded`, "a discarded window's old file
    survived";
  - without removing discarded keys from the registry, the same failure plus
    "a discarded key stayed live".
- **Not verified:**
  - a real `didDiscardSceneSessions` from the system (the simulator's
    iPhone never produced one, and no iPad or visionOS window was closed by
    hand);
  - adoption between two real windows.
- **Not built:**
  - choosing which orphan to adopt (always the newest);
  - telling the user the changes came from another window (since built:
    ADR 0015);
  - macOS.

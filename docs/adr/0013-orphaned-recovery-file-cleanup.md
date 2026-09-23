# ADR 0013: Cleaning up orphaned recovery files

Status: Accepted (2026-09-23)

## Context

ADR 0012 keeps an Untitled document's unsaved changes in
`Application Support/GamaStudio Recovery/<key>.usda`, keyed by the window's
scene session. It listed one gap: a window closed for good (on iPad or
visionOS, or a session the system discards) leaves its file behind, and
nothing ever removes it. A recovery file that could not be read is also set
aside as `<key>.unreadable-<time>.usda` and kept indefinitely.

Donald asked for cleanup on 2026-09-23 and chose a grace period: keep an
orphan for 7 days, in case its window comes back, then delete it. The other
choices were moving orphans somewhere visible in Files, which never
discards work but exposes the app's Documents folder, or deleting them
immediately.

## Decision

1. **Which files count as orphans.** `UntitledRecovery.sweepOrphans(in:keeping:now:gracePeriod:)`
   (platform-neutral) deletes:
   - a `<key>.usda` whose key is not in the live set;
   - a `<key>.unreadable-<time>.usda`;

   once either has gone unmodified for `orphanGracePeriod` (7 days). Files
   with any other name (another extension, an invalid key, another second
   part) are never touched. It returns what it deleted.
2. **The live set is the app's scene sessions.** On iOS and visionOS,
   `StudioHostViewController` sweeps on each window's first appearance, right
   after restoring. The live set is `UIApplication.shared.openSessions`
   (every window the system still keeps, connected or not) plus this
   window's key, which the gate passes explicitly. A window the system still
   keeps never loses its file, however old.
3. **The clock.** The grace period runs from the file's modification date.
   A live window's autosaves keep its file fresh, but a live window is never
   swept anyway. For an orphan, the clock starts at its last autosave. Setting
   an unreadable file aside now also stamps it with the current time, because
   a rename keeps the old date, and the file would otherwise be deleted by
   the next sweep for being as old as the recovery it came from.
4. **Gate.** Before each simulator's recovery launch, the gate plants an
   orphan dated 8 days back and one dated now. After the launch, the first
   must be gone and the second present, and the gate removes it.

## Consequences

- **macOS unit tests** (`UntitledRecoveryTests`) cover:
  - only orphans past the grace period go, including set-aside files;
  - a live key's file stays at four times the grace period;
  - four kinds of foreign file stay;
  - a missing directory is harmless;
  - a freshly set-aside file survives the next sweep.
- **Mutation checks, both failing as intended:**
  - without the date stamp in `moveAside`, the set-aside test fails;
  - without the host's sweep call, the planted 8-day orphan survives the
    simulator launch.
- **Verified in the iPhone 17 simulator by hand**, with the same steps as
  the gate: the 8-day orphan went, and the fresh orphan and the window's own
  session file stayed.
- **This does discard work.** A window closed with unsaved Untitled changes
  loses them 7 days later, without asking. That is the chosen trade: nothing
  new appears in Files, and orphans cannot pile up.
- **Not built:**
  - sweeping when the system discards a session while the app runs
    (`application(_:didDiscardSceneSessions:)`); the next launch catches it;
  - any way to see or reopen an orphan during its grace period;
  - macOS, which has no recovery files.

# Distinct-identity shared shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin the existing rule that two enabled controls with different `ActionID` values and one non-reserved shortcut leave both identities callable, while the shortcut runs the later registration.

**Architecture:** `HostActionStore.registerNamed` assigns `named[id] = action` and, for a non-reserved shortcut, `shortcuts[shortcut] = id`. A later control with a different identity does not erase the earlier identity. `FrameHost.perform(_:)` reads `named`. A key that the focused control does not consume reads `shortcuts`. Enter still runs the focused node's own closure, which is a different map.

**Tech Stack:** Swift 6.5-dev selected by `swiftly run swift` after `unset TOOLCHAINS`, Swift Testing, a scratch path outside this FileProvider checkout.

---

## Out of scope for this file

This file plans one test. It does not change mode sequences, color depth, the rescue buffer, or the testing catalog.

### Task 1: Pin a shared shortcut across two identities

**Files:**
- Modify: `Tests/gamaTests/ActionIdentityTests.swift`
- Read, and change only if the new test fails: `Sources/GamaCore/FrameHost.swift` (`registerNamed`, lines 55-59)
- Test: `Tests/gamaTests/ActionIdentityTests.swift`

- [ ] **Step 1: Add the app and the test**

Insert this app next to `OverlapApp` in `Tests/gamaTests/ActionIdentityTests.swift`.

```swift
private struct DistinctShortcutApp: App {
    let early = Signal(0)
    let late = Signal(0)

    init() {}

    var scenes: some Scene {
        Window("Distinct", id: "main", role: .primary) {
            VStack {
                Button("Early") { early.set(early.get() + 1) }
                    .actionIdentity(ActionID("early"), shortcut: .ctrl("a"))
                Button("Late") { late.set(late.get() + 1) }
                    .actionIdentity(ActionID("late"), shortcut: .ctrl("a"))
            }
        }
    }
}
```

Insert this test inside `ActionIdentityTests`, after `laterRegistrationWins`.

```swift
@Test("a shared shortcut follows the later identity and the earlier identity remains")
func distinctIdentitySharedShortcut() throws {
    let app = DistinctShortcutApp()
    var host = try FrameHost(app: app)
    _ = host.pump(size: Size(width: 40, height: 8))

    host.handle(.key(.enter))
    #expect(app.early.get() == 1)
    #expect(app.late.get() == 0)

    host.handle(.key(.ctrl("a")))
    #expect(app.early.get() == 1)
    #expect(app.late.get() == 1)

    host.perform(ActionID("early"))
    #expect(app.early.get() == 2)
    #expect(app.late.get() == 1)

    host.perform(ActionID("late"))
    #expect(app.early.get() == 2)
    #expect(app.late.get() == 2)
}
```

The first button is focused, so Enter runs that node's closure and increments `early`. Ctrl-A is not consumed by the button, so the shortcut map runs the later identity. `perform` still finds both identities.

- [ ] **Step 2: Run the new test**

Create a scratch directory outside this checkout, then run:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /var/folders/42/07tmt0n56jq4261xb9gz5jwm0000gn/T/gama-shared-shortcut/spm \
  --filter distinctIdentitySharedShortcut
```

Expected when `registerNamed` keeps last-write-wins: `Test run with 1 test in 1 suite passed`.

If Ctrl-A increments `early` instead of `late`, the shortcut map kept the first registration. If `perform(ActionID("early"))` does not increment `early`, the identity map was overwritten. Either result is a failure of this test. A filter that prints `No matching test cases were run` is a failure even when the process exits 0.

- [ ] **Step 3: Keep the assignment that the test describes**

`Sources/GamaCore/FrameHost.swift` already assigns both maps:

```swift
func registerNamed(_ id: ActionID, shortcut: Key?, action: @escaping () -> Void) {
    named[id] = action
    if let shortcut, !isReservedActionShortcut(shortcut) {
        shortcuts[shortcut] = id
    }
}
```

Leave that function as an assignment of `shortcuts[shortcut]`, not an insert that returns when the key is already present. Leave `named[id] = action` as an assignment of that identity only. Do not edit this function when step 2 already reports 1 passing test.

- [ ] **Step 4: Run the suite**

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /var/folders/42/07tmt0n56jq4261xb9gz5jwm0000gn/T/gama-shared-shortcut/spm \
  --filter ActionIdentityTests
```

Expected: `Test run with 8 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Tests/gamaTests/ActionIdentityTests.swift
git commit -m "$(cat <<'EOF'
test(core): pin a shared shortcut across two identities

Ctrl-A runs the later control. perform still reaches the earlier
ActionID. Enter still activates the focused node.
EOF
)"
```

# Inspector — draft

Status: Draft. Open questions, not a commitment. Nothing here is built.

## A naming collision to clear first

Searching the tree for "Inspector" returns hits, and none of them are this.
`Sources/GamaAppleDemo/main.swift` declares an auxiliary window literally
titled "Inspector" (`Window("Inspector", id: "inspector")`), referenced
from `docs/SceneMigration.md` and `docs/backends/AppleShell.md` as a
multi-window example. It is demo content, not a devtool. A future search
will find it again; it is not a starting point.

## Why an inspector is cheap here and expensive elsewhere

Most of what an inspector displays is already a value in this architecture
rather than something to be recovered from a running UI:

- The semantic tree is `RenderNode`, a `Hashable` value IR.
- The laid-out tree is `LaidOutNode` — the same nodes with absolute frames
  and children, already returned directly by `FrameHost.pump(size:)`.
- The accessibility tree is derived portably by `AccessibilitySnapshot` in
  `GamaDraw`, from the `DrawList`, not scraped from pixels.
- Focus, actions, and duplicate identities are already observable:
  `FrameHost` exposes `focusedID`, `duplicateIDs`, and
  `transientStateIDs`, the last being a real diagnostic for state that was
  reconstructed instead of preserved.
- Reactive storage is countable; `HostStateStore.count` exists and the
  tests already use it as a leak baseline.

So the data model is largely a read of things that exist. What does not
exist is a *presentation* of them and a way to reach a live process.

## Two shapes, and they are not the same project

**Offline inspection** takes a tree that a host already returned and
renders it — as text for a CLI, or as a Gama app in a terminal. It needs
no new runtime surface at all, only a formatter and a command. It is
small, and almost all of its value is available immediately.

**Live inspection** attaches to a running process, which is the remote UI
problem wearing a different hat: a transport, a handshake, and a decision
about what a peer may ask for. See the remote UI draft beside this one.
The manifesto's §188 wants the inspector to distinguish local from remote
state and transport from renderer latency, which only matters once live
attachment exists.

## Open questions

1. Offline first? It is separable, has no protocol, and would exercise the
   formatter that live inspection later reuses.
2. Where would it live? A new executable target keeps it out of shipped
   library products, which matters because the zero-runtime-dependency and
   portable-import rules apply to everything under the boundary gate's
   `TARGETS` list.
3. What does it show about *performance*? `gama-bench` measures the frame
   path deterministically and asserts no threshold on purpose
   (`docs/Performance.md`). An inspector that reported timings would be
   making measurements a benchmark deliberately refuses to turn into a
   gate; the honesty rules around that need deciding before, not after.
4. Does inspection need an authorization story even locally? The manifesto
   (§187) says automation must be permission-controlled. A read-only
   offline dump of a tree the caller already owns arguably needs none,
   which is another argument for doing that half first.

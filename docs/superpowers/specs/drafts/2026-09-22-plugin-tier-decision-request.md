# Plugin Tiers 2 and 3 — decision request

Status: Draft. This asks two questions rather than answering them. It is
deliberately **not** a design, because writing one would presume answers
that are the project owner's to give.

## Why this is a request and not a spec

`tasks/todo.md` lists Tiers 2 and 3 under deferred product scope with the
note that neither is committed implementation work and each needs a new
accepted design before execution. The superseded plugin runtime draft
(`2026-08-26-plugin-runtime-draft.md`, §6) left two questions open, and the
approved spec that replaced it did not resolve them — it reaffirmed "Tier 2
remains Proposed post-V1; Tier 3 remains future." They are still open.

## Where Tier 1 actually stands

A plugin today is a `GamaPluginProtocol`-conforming Swift value, statically
registered by the application — no discovery, because wasm32 and Embedded
cannot enumerate anything at runtime. Its manifest declares capabilities
from a closed three-case enum (`.log`, `.clock`, `.filesystem(scope)`);
grants are deny-by-default and exact-match; a missing grant or a missing
service fails the whole install closed; granted capabilities arrive as
handle structs with internal initializers, so they cannot be forged outside
the module.

`docs/Plugins.md` is emphatic that this is capability-based *design*, not a
sandbox: the plugin is linked into the process and can import Foundation
and do as it likes. `docs/Capabilities.md` preserves that honesty in a
standing line — no sandbox claim exists for in-process tiers. Any answer
below must keep that sentence true rather than quietly softening it.

## Question 1 — is Tier 2 wanted at all?

Tier 2 as sketched is `dlopen`/`LoadLibraryW` of a versioned flat C entry
point family, feeding the same `PluginRuntime.install` path. Crucially it
**adds no isolation**: same address space, same trust story. What it adds
is a load-time decision — you can check a signature before you run
somebody's code — and the ability to ship a plugin without recompiling the
host.

The draft itself notes that Tauri, the comparison point, ships static-only
plugin linkage, and asks whether static plus out-of-process covers every
real use, making Tier 2 skippable.

It is not free: the manifest is currently Swift code and has never been
serialized, so Tier 2 needs a manifest wire encoding, a C entry-point
convention, a boundary-gate extension for the new target, and a
fixture-dylib harness with hostile-input coverage.

## Question 2 — is Tier 3 "future," or is it the point?

Tier 3 is the only tier where capabilities would be *enforced* rather than
promised, because a separate process can only act through the message ABI.
If the plugin story is ever going to be described to anyone as sandboxed,
this is the tier that makes the sentence true, and the draft asks directly
whether that means its message ABI deserves design time now rather than
later.

What it would cost, concretely — and none of this exists today, confirmed
by a repository-wide search finding no `Process`, XPC, `posix_spawn`, or
sandbox API usage anywhere:

- a length-prefixed message ABI (the pieces that are already plain data —
  `CapabilityGrants`, `PluginManifest`, encoded `DrawList` bytes — are
  encouraging, but no wire protocol is designed);
- process lifecycle: spawn, handshake, crash and hang detection, teardown;
- RPC for `HostServices`, whose capabilities are closures today and cannot
  cross a process boundary as such;
- a `.network` capability, which is reserved in prose and not even present
  in the shipped `Capability` enum;
- platform sandboxing to back the isolation claim — plausible on macOS via
  App Sandbox, with nothing analogous scoped for Linux or Windows.

There is also a sequencing question worth deciding at the same time: Tier
3's transport and the remote UI protocol (see the draft beside this one)
are the same problem — capability-negotiated transport across a process
boundary — and designing them independently would likely produce two
incompatible answers.

## What would unblock the work

An answer to each question. If Tier 2 is unwanted, that alone is a useful
decision: it removes an entire intermediate design from the roadmap. If
Tier 3 is the point rather than the future, its message ABI is the next
plugin design task, and the remote UI protocol should be designed with it
rather than after it.

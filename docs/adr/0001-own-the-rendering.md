# 0001 — Own the rendering

Status: Accepted (locked in the sub-project 1 foundation spec,
`../superpowers/specs/2026-08-26-gama-umbrella-foundation-design.md`, which
is the authoritative text; this record indexes it).

## Context

The umbrella goal is a Tauri/React-Native-class cross-platform framework.
The alternatives were wrapping each platform's native widgets, embedding a
webview, or owning a retained rendering pipeline.

## Decision

Gama owns rendering end to end: views compile to a pure-value `RenderNode`
IR, one `LayoutEngine` and one `CellPainter`/`DrawList` drawing layer are
shared by every backend, and backends only translate events in and present
frames out. The former Qt adapter was removed rather than maintained as a
second semantic.

## Consequences

Visual and interaction semantics cannot fork per platform; every new
backend costs only event translation and presentation; the price is that
platform-native affordances (accessibility, IME, dynamic type) must be
built deliberately from the shared IR rather than inherited from widgets.

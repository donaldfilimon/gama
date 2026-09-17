# ``GamaDraw``

Rasterize laid-out trees into cells once and present them from any backend.

## Overview

GamaDraw is the platform-free drawing layer between GamaCore's layout output
and every presentation backend. ``CellPainter`` walks a `LaidOutNode` tree
into a ``CellBuffer`` — a double-buffered character grid — so terminals, GUI
views, browser DOM, and C embedding hosts all paint pixel-identically; a
backend only decides how cells reach the screen.

Two presentation families sit on that same buffer and must not be unified.
``CellPresenter`` is mutating and swaps planes: ``AnsiPresenter`` wraps
``CellBuffer/presentDiff()`` for an interactive terminal, and
``StreamPresenter`` emits a chronology of changed rows for a pipe or log.
``CellSerializer`` is non-mutating and does not swap: ``DrawListSerializer``
names the wholesale ``DrawList`` derivation that Embed and Apple already
perform. Nothing in the tree is generic over ``CellSerializer``; it constrains
conformers, not consumers, and is not a plug-in point.

Vector hosts run-merge the grid into a
``DrawList`` of backend-neutral commands, either consumed directly (Apple,
browser) or shipped across the C ABI as the versioned little-endian binary
encoding (magic `GAMA`, version 1). ``DrawList/decode(_:)`` treats input as
untrusted and throws a precise ``DrawList/DecodeError`` for the first wire
violation.

The wire format and embedding walkthrough live in the GamaCore catalog's
"C embedding and DrawList wire format" article and `docs/backends/CEmbed.md`;
this module documents the drawing API itself.

## Topics

### Cell raster

- ``Cell``
- ``CellBuffer``
- ``CellPainter``

### Terminal presentation

- ``CellPresenter``
- ``AnsiPresenter``
- ``StreamPresenter``

### Wholesale serialization

- ``CellSerializer``
- ``DrawListSerializer``

### Vector commands and wire format

- ``DrawCommand``
- ``DrawList``
- ``DrawList/DecodeError``

### Assistive-technology text

- ``AccessibilitySnapshot``
- ``AccessibilitySnapshot/Line``

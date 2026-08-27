# ``GamaDraw``

Rasterize laid-out trees into cells once and present them from any backend.

## Overview

GamaDraw is the platform-free drawing layer between GamaCore's layout output
and every presentation backend. ``CellPainter`` walks a `LaidOutNode` tree
into a ``CellBuffer`` — a double-buffered character grid — so terminals, GUI
views, browser DOM, and C embedding hosts all paint pixel-identically; a
backend only decides how cells reach the screen.

Terminals flush the buffer's differential ANSI stream
(``CellBuffer/presentDiff()``). Vector hosts run-merge the grid into a
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

### Vector commands and wire format

- ``DrawCommand``
- ``DrawList``
- ``DrawList/DecodeError``

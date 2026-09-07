#!/usr/bin/env python3
"""Close the two escape hatches Swift 6 leaves open for process-global state.

AGENTS.md: "framework state must not move into process-global registries."
`check-boundaries.sh` enforced that with three string literals — `ActionRegistry`,
`Invalidator.shared`, and `nonisolated(unsafe).*_host` — so a global named
anything else passed. That is gap H1 of the unenforced-policy audit.

Measured against the pinned compiler on 2026-09-06 rather than assumed, because
the answer narrows the rule considerably. Every target builds in Swift 6
language mode, and that mode already rejects the common case on its own:

    static var probeCounter = 0
    error: static property 'probeCounter' is not concurrency-safe because it is
           nonisolated global shared mutable state

So no stored-versus-computed heuristic is needed; the compiler is
self-enforcing there, the way ADR 0006's `AppRuntime` turned out to be. What
the compiler still accepts — both verified to build clean in `GamaPlugin` — are
the two deliberate escape hatches:

    nonisolated(unsafe) static var probeCounter = 0   # compiles, 0 errors
    @MainActor static var probeCounter = 0            # compiles, 0 errors

Those are what this checks. Both are legitimate elsewhere: `GamaWASM` uses
`nonisolated(unsafe)` for its installed host with a written single-threaded
justification, and backends are isolated by nature. Neither belongs in a
portable target.

The global-actor ban is deliberately one step wider than "no global state": it
rejects the attribute even on a function, because isolation couples a portable
target to a concurrency runtime it must not require. Only `GamaCore` is
compiled by `check-embedded.sh`, so for the other four this gate is the only
thing saying so.

Known boundary, stated rather than pretended away: a `static let` bound to a
reference type with mutable interior is process-global state that neither the
compiler nor this script rejects. No such binding exists in these targets today
(every `static let` is a value-type constant), and catching it needs type
information, not text.

Fail-closed: a missing target directory or a target with no Swift files fails,
so a rename cannot quietly reduce this to checking nothing.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Portable and platform-free targets. Backends are excluded on purpose: see the
# GamaWASM justification above.
TARGETS = ("GamaCore", "GamaPlugin", "GamaDraw", "GamaEmbed", "GamaMLIR")

UNSAFE = re.compile(r"nonisolated\s*\(\s*unsafe\s*\)")
GLOBAL_ACTOR = re.compile(r"@(?:MainActor|globalActor|[A-Z]\w*Actor)\b")

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)


def strip_noncode(text: str) -> str:
    """Reduce a file to code, so a *mention* of a hatch is not a use of one.

    Two shapes must not fail. `Sources/GamaWASM/WASMHost.swift:87` is prose
    naming `nonisolated(unsafe)` to justify the declaration below it, and a
    string literal may quote the same attribute. Both are blanked; blanking
    rather than deleting keeps every line number intact for the report.

    Line comments are cut only outside string literals, so a `//` inside a
    string cannot swallow real code after it. The walk is line-scoped and does
    not understand multi-line (`\"\"\"`) literals: it would blank the tail of the
    opening line and then read the literal's interior as code, which is
    under-reporting on one line and over-reporting on the rest. That is not a
    safe ambiguity to leave implicit, so `check` rejects any `\"\"\"` in scope
    outright rather than this docstring promising behavior the walk lacks.
    """
    text = BLOCK_COMMENT.sub(lambda m: " " * len(m.group()), text)
    out: list[str] = []
    for line in text.splitlines():
        rendered: list[str] = []
        quoted = False
        index = 0
        while index < len(line):
            char = line[index]
            if quoted and char == "\\":
                rendered.append("  ")
                index += 2
                continue
            if char == '"':
                quoted = not quoted
                rendered.append(" ")
            elif quoted:
                rendered.append(" ")
            elif char == "/" and line.startswith("//", index):
                rendered.append(" " * (len(line) - index))
                break
            else:
                rendered.append(char)
            index += 1
        out.append("".join(rendered))
    return "\n".join(out)


def scan_text(text: str, name: str) -> list[str]:
    failures: list[str] = []
    for number, line in enumerate(strip_noncode(text).splitlines(), start=1):
        if UNSAFE.search(line):
            failures.append(
                f"error: {name}:{number}: `nonisolated(unsafe)` in a portable "
                f"target. Swift 6 rejects nonisolated global mutable state on "
                f"its own; this attribute is the hatch around it, and portable "
                f"framework state must be owned by a host, not by the process."
            )
        if GLOBAL_ACTOR.search(line):
            failures.append(
                f"error: {name}:{number}: global-actor isolation in a portable "
                f"target. It is the second hatch to process-global state and it "
                f"couples the target to a concurrency runtime it must not "
                f"require."
            )
    return failures


def check(root: Path) -> list[str]:
    failures: list[str] = []
    for target in TARGETS:
        directory = root / "Sources" / target
        if not directory.is_dir():
            failures.append(
                f"error: portable target {target} is missing from Sources/; "
                f"this gate stopped checking it rather than failing loudly"
            )
            continue
        sources = sorted(directory.rglob("*.swift"))
        if not sources:
            failures.append(f"error: portable target {target} has no Swift sources")
            continue
        for path in sources:
            text = path.read_text(encoding="utf-8")
            name = str(path.relative_to(root))
            # The comment/string walk is line-scoped. A multi-line literal would
            # make it read the literal's interior as code, so refuse rather than
            # guess: none exists in these targets today, and one appearing is a
            # reason to write a real lexer, not to trust this one.
            if '"""' in text:
                failures.append(
                    f"error: {name}: multi-line string literal in a portable "
                    f"target; scripts/portable-global-state.py scans line by "
                    f"line and cannot tell that literal's interior from code"
                )
                continue
            failures += scan_text(text, name)
    return failures


def self_test() -> None:
    # The two hatches, in the exact shapes measured to compile.
    for hatch, expected in (
        ("    nonisolated(unsafe) static var probeCounter = 0", "nonisolated(unsafe)"),
        ("    @MainActor static var probeCounter = 0", "global-actor"),
    ):
        caught = scan_text(hatch, "probe.swift")
        assert len(caught) == 1, f"expected one failure for {hatch!r}, got {caught}"
        assert expected in caught[0], caught[0]

    # A custom global actor is the same hatch under another name.
    assert scan_text("    @RenderActor static var x = 0", "probe.swift")

    # Prose describing a hatch is not a use of one. This is the real shape of
    # Sources/GamaWASM/WASMHost.swift:87.
    for benign in (
        "    /// entire justification for `nonisolated(unsafe)` here; a threaded wasm",
        "    // @MainActor would couple this to a runtime",
        "    /* nonisolated(unsafe) is banned here */",
        "    public static var unavailable: WindowActions {",
        "    public static let zero = Point(x: 0, y: 0)",
        '    let note = "see nonisolated(unsafe) // in the ADR"',
    ):
        assert not scan_text(benign, "probe.swift"), f"false positive: {benign}"

    # A line comment must not swallow code that precedes it on the same line.
    assert scan_text(
        "    nonisolated(unsafe) static var x = 0 // justified", "probe.swift"
    )

    # The multi-line-literal refusal is checked in `check`, not `scan_text`,
    # because it is about what this scanner cannot read rather than what it
    # found. Pin the walk's actual weakness so the refusal stays justified:
    # the interior of such a literal is read as code.
    assert scan_text('let s = """\n@MainActor\n"""', "probe.swift"), (
        "multi-line literal interiors are read as code; the refusal in check() "
        "is what keeps that from mattering"
    )
    print("OK — portable global-state checker self-test")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    failures = check(args.root.resolve())
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"OK — no process-global hatches in {', '.join(TARGETS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

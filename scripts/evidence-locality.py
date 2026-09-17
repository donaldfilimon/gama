#!/usr/bin/env python3
"""Keep anchored evidence claims in the one file that is checked for staleness.

`scripts/evidence-freshness.py` fails a claim whose anchor predates the changes
it depends on, but its reach is one file: `LEDGER = "docs/Capabilities.md"`. Any
other document may therefore state "Hosted proven at <commit>" and go stale in
silence, with every gate green.

That is not hypothetical. `docs/Packaging.md` carried a second, hand-maintained
copy of the packaged-wasm evidence — anchored to `77812d99`, naming Pages run
`33919361438` and a 9,297,539-byte artifact. Both copies were written together
by `8bb838b` on 2026-09-04. The ledger retired that byte figure as stale in
`a4c7a5c` on 2026-09-06 15:36, because both the bundler and the bundled source
had changed; `docs/Packaging.md` went on asserting it, and was still asserting
it when this gate landed under two hours later. Nothing would have caught the
divergence at any point — the duplicate simply stopped agreeing. The ledger's
own rule says to update the capability guide once and link to it. Nothing
enforced the rule.

So: an anchored evidence claim outside the ledger is an error. Point at the
ledger row instead. Measurement conditions are not claims — `docs/Performance.md`
naming the commits a benchmark ran at, and `docs/Toolchain.md` naming a compiler
revision, are exactly the provenance this repository wants and are untouched.

Fail-closed in two ways that matter:
  * Zero scanned files fails. A path rename must break loudly rather than
    quietly reduce this to checking nothing — the lesson `check-toolchain-pins.sh`
    learned by enumerating five scripts while ten needed checking.
  * The self-test asserts both directions: a planted violation is caught, and a
    real measurement-conditions line is not.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

LEDGER = Path("docs/Capabilities.md")

# The declared evidence layers of docs/Capabilities.md's status vocabulary.
# "Implemented" and "Blocked" are excluded deliberately: neither asserts a run,
# so neither can go stale against an anchor.
LAYERS = r"(?:Hosted|Locally|Manually|Artifact)"

# An evidence claim anchored to a commit: a layer word, then "proven", then a
# backticked 7-40 hex sha before the end of the sentence or table cell.
ANCHORED_CLAIM = re.compile(
    rf"\b{LAYERS}\b[^.|]{{0,120}}?\bproven\b[^.|]{{0,120}}?`[0-9a-f]{{7,40}}`",
    re.IGNORECASE,
)

# A CI run id. Only the ledger may name one; elsewhere it is an unowned claim.
RUN_ID = re.compile(r"\brun\s+`?\d{8,}`?", re.IGNORECASE)

ROOT_DOCS = ("README.md", "CONTRIBUTING.md", "AGENTS.md", "CLAUDE.md")


def _paragraphs(text: str) -> list[tuple[str, list[tuple[int, int]]]]:
    """Join each hard-wrapped block into one searchable string.

    Every document here wraps at ~80 columns, so a claim and its anchor
    routinely land on different physical lines. A line-scoped search catches
    the table-cell form and misses the paragraph form entirely. Joining is safe
    across table rows because both patterns exclude `|`, which every row is
    full of, so a match can never span two cells.

    Returns the joined text plus, for each source line, its (start, line
    number) offset into that text, so a match reports the line it began on.
    """
    blocks: list[tuple[str, list[tuple[int, int]]]] = []
    current: list[tuple[int, str]] = []

    def flush() -> None:
        if not current:
            return
        joined, spans, offset = "", [], 0
        for number, line in current:
            spans.append((offset, number))
            joined += line + " "
            offset += len(line) + 1
        blocks.append((joined, spans))
        current.clear()

    for number, line in enumerate(text.splitlines(), start=1):
        if line.strip():
            current.append((number, line))
        else:
            flush()
    flush()
    return blocks


def _line_of(spans: list[tuple[int, int]], offset: int) -> int:
    line = spans[0][1]
    for start, number in spans:
        if start > offset:
            break
        line = number
    return line


def scan_text(text: str, name: str) -> list[str]:
    failures: list[str] = []
    for joined, spans in _paragraphs(text):
        for match in ANCHORED_CLAIM.finditer(joined):
            failures.append(
                f"error: {name}:{_line_of(spans, match.start())}: evidence "
                f"claim anchored to a commit outside {LEDGER}. Only that file "
                f"is checked for staleness by "
                f"scripts/check-evidence-freshness.sh; state the claim in its "
                f"row and link to it here."
            )
        for match in RUN_ID.finditer(joined):
            failures.append(
                f"error: {name}:{_line_of(spans, match.start())}: CI run id "
                f"outside {LEDGER}. A run id is evidence and belongs in the "
                f"anchored row that owns it."
            )
    return failures


def targets(root: Path) -> list[Path]:
    found = sorted(p for p in (root / "docs").rglob("*.md") if p != root / LEDGER)
    found += [root / n for n in ROOT_DOCS if (root / n).is_file()]
    return found


def check(root: Path) -> list[str]:
    files = targets(root)
    if not files:
        return [
            "error: evidence-locality scanned zero files; the documentation "
            "layout moved and this gate silently stopped checking anything"
        ]
    if not (root / LEDGER).is_file():
        return [f"error: {LEDGER} is missing; the evidence ledger is the anchor"]
    failures: list[str] = []
    for path in files:
        failures += scan_text(
            path.read_text(encoding="utf-8"), str(path.relative_to(root))
        )
    return failures


def self_test() -> None:
    violation = (
        "| Pages serves the demo | workflow | Hosted proven 2026-09-04 at merge "
        "commit `77812d99`: Pages run `33919361438` deployed |"
    )
    caught = scan_text(violation, "probe.md")
    assert len(caught) == 2, f"expected both rules to fire, got {caught}"
    assert "anchored to a commit" in caught[0]
    assert "CI run id" in caught[1]

    # The hard-wrapped paragraph form. Every document here wraps at ~80
    # columns, so this is the shape a claim actually takes in prose, and a
    # line-scoped search misses it. The line number must be where the claim
    # began, not where the anchor happened to land.
    wrapped = (
        "The gate change went out as PR #82.\n"
        "Hosted proven at `0d4cf12`, re-verified from run state 2026-09-06:\n"
        "  run `34049182287` completed with all six required jobs green.\n"
    )
    caught = scan_text(wrapped, "probe.md")
    assert len(caught) == 2, f"wrapped claim not caught: {caught}"
    assert "probe.md:2:" in caught[0], caught[0]
    assert "probe.md:3:" in caught[1], caught[1]

    # A blank line ends a paragraph, so an unrelated later anchor must not be
    # welded onto an earlier layer word.
    split = "Hosted proven by the macOS bundle step.\n\nSee `b01e606` for the\nbenchmark conditions.\n"
    assert not scan_text(split, "probe.md"), scan_text(split, "probe.md")

    # Measurement conditions are provenance, not a layered claim.
    for benign in (
        "| noncopyable `Terminal` (`8b5d260`) | 6,683 ns |",
        "Conditions: commit `b01e606`, pinned `main-snapshot-2026-08-21`, release",
        "| Compiler | Apple Swift 6.5-dev, Swift `95c5142e84b82c1` |",
        "This reruns the native-host scenario after `dc3f21b` made the four",
        "See the `Packaged wasm site` row of [`Capabilities.md`](Capabilities.md).",
    ):
        assert not scan_text(benign, "probe.md"), f"false positive on: {benign}"
    print("OK — evidence locality checker self-test")


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
    print("OK — every anchored evidence claim lives in the ledger")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

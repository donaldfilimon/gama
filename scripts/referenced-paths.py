#!/usr/bin/env python3
"""Fail when documentation names a repository path the tree does not contain.

It reads the working tree, so locally it describes what is on disk; it becomes
a statement about a commit only once it lands and CI runs it against that
commit's checkout. The distinction matters: this gate passes in a working tree
whose uncommitted files satisfy a claim that the commit would not.

`scripts/evidence-freshness.py` asks whether a claim's sources have *moved*
since it was proven. Nothing asked the prior question: whether the thing a
claim names exists at all. The two failures look nothing alike, and only the
first was gated.

Observed in this repository on 2026-09-06, which is why this exists. Commit
`a69566a` landed `tasks/todo.md` bullets describing
`scripts/evidence-locality.py` and `scripts/portable-global-state.py`, and
stating they are chained from `check-docs.sh` and `check-boundaries.sh`, while
both scripts and both chain lines were still uncommitted in a working tree. At
that commit the ledger asserted two gates the tree did not have, and every gate
stayed green, because nothing checked that a named path was present. The same
shape lets a reference to a deleted script survive a cleanup indefinitely.

Scope is deliberately narrow, from measurement rather than taste. A first pass
over every backticked filename found 121 "broken" references that were nothing
of the kind: prose naming a file by its bare name (`FrameHost.swift`), or by a
module-relative fragment (`GamaCore/HostPump.swift`). Those are how people
write, not path claims, and failing them would force 121 edits to buy nothing.
Only a **root-anchored** path is treated as a claim: one beginning with a
top-level directory of this repository, or naming a known root file. That
restriction cut the false set from 121 to 7.

The remaining 7 were all in `docs/superpowers/plans/` and
`docs/superpowers/specs/drafts/`, naming files those documents *propose* to
create. CLAUDE.md is explicit that drafts are "open questions, not commitments"
and that neither plans nor specs are capability claims, so both trees are
excluded and a proposal may name a file that does not exist yet. Accepted specs
are **not** excluded: an accepted design naming a missing path is the defect
this gate is for.

Fail-closed: zero scanned files or zero extracted references fails, so a
documentation reshuffle must break loudly rather than quietly check nothing.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Top-level directories of this repository. A backticked string starting with
# one of these is a path claim; anything else is prose naming a file.
ROOT_DIRECTORIES = (
    "scripts/",
    "Sources/",
    "Tests/",
    "docs/",
    "tasks/",
    "Examples/",
    "WebHost/",
    "Distribution/",
    ".github/",
    ".agents/",
    ".claude/",
)

ROOT_FILES = frozenset(
    {
        "Package.swift",
        "Package.resolved",
        "Toolchains.toml",
        "README.md",
        "AGENTS.md",
        "CLAUDE.md",
        "CONTRIBUTING.md",
    }
)
# `.swift-version` is deliberately absent. REFERENCE matches `<stem>.<ext>` with
# at least one character before the dot, so a leading-dot name can never reach
# is_claim(); listing it would be a dead allowlist entry in a fail-closed gate,
# which is worse than not covering it. Covering it means matching dotfiles, a
# different pattern and its own decision.

# Proposals may name what they propose. See the docstring.
EXCLUDED_TREES = ("docs/superpowers/plans/", "docs/superpowers/specs/drafts/")

# A backticked path with a real file extension, optionally suffixed `:<line>`.
REFERENCE = re.compile(
    r"`([A-Za-z0-9_./-]+\.(?:swift|sh|py|md|toml|json|yml|c|h|mjs|txt|resolved)"
    r"(?::\d+)?)`"
)


def is_claim(candidate: str) -> bool:
    """True when the string is a root-anchored path rather than prose."""
    return candidate.startswith(ROOT_DIRECTORIES) or candidate in ROOT_FILES


def references(text: str) -> list[tuple[int, str]]:
    """Every root-anchored path claim, as (line number, path without :line)."""
    found: list[tuple[int, str]] = []
    for number, line in enumerate(text.splitlines(), start=1):
        for match in REFERENCE.finditer(line):
            candidate = match.group(1).split(":")[0]
            if is_claim(candidate):
                found.append((number, candidate))
    return found


def documents(root: Path) -> list[Path]:
    found = sorted((root / "tasks").glob("*.md"))
    found += sorted((root / "docs").rglob("*.md"))
    found += [root / n for n in sorted(ROOT_FILES) if n.endswith(".md") and (root / n).is_file()]
    return [
        p
        for p in found
        if not str(p.relative_to(root)).startswith(EXCLUDED_TREES)
    ]


def check(root: Path) -> list[str]:
    files = documents(root)
    if not files:
        return [
            "error: referenced-paths scanned zero documents; the layout moved "
            "and this gate silently stopped checking anything"
        ]
    failures: list[str] = []
    total = 0
    for path in files:
        name = str(path.relative_to(root))
        for number, target in references(path.read_text(encoding="utf-8")):
            total += 1
            if not (root / target).exists():
                failures.append(
                    f"error: {name}:{number}: names `{target}`, which is not in "
                    f"the tree. Documentation may not assert a path the tree "
                    f"does not contain; add the file, fix the path, or move the "
                    f"claim to a plan or draft, where proposals belong."
                )
    if total == 0:
        failures.append(
            "error: referenced-paths extracted zero path claims from "
            f"{len(files)} documents; the reference pattern stopped matching "
            "and this gate is checking nothing"
        )
    return failures


def self_test() -> None:
    # Prose is not a claim. These are the shapes the 121-reference first pass
    # wrongly flagged.
    for prose in ("`FrameHost.swift`", "`GamaCore/HostPump.swift`", "`Capabilities.md`"):
        assert not references(prose), f"prose treated as a claim: {prose}"

    # Root-anchored paths are claims, and a :line suffix is stripped.
    assert references("see `scripts/check-docs.sh` now") == [(1, "scripts/check-docs.sh")]
    assert references("`Sources/GamaCore/FrameHost.swift:38`") == [
        (1, "Sources/GamaCore/FrameHost.swift")
    ]
    assert references("`Package.swift`") == [(1, "Package.swift")]
    # Pin the reason `.swift-version` is not in ROOT_FILES: the pattern needs a
    # stem before the dot, so a leading-dot name is unreachable and an allowlist
    # entry for it would be dead code inside a fail-closed gate.
    assert not references("`.swift-version`")
    assert ".swift-version" not in ROOT_FILES
    # A path without a recognized extension is not matched at all.
    assert not references("`scripts/lib`")
    # Line numbers are reported from the line the reference sits on.
    assert references("first\nsecond `tasks/todo.md`") == [(2, "tasks/todo.md")]

    # The excluded trees are matched on the relative path, so a nested plan is
    # excluded too.
    assert str(Path("docs/superpowers/plans/x.md")).startswith(EXCLUDED_TREES)
    assert not str(Path("docs/superpowers/specs/accepted.md")).startswith(EXCLUDED_TREES)

    print("OK — referenced-paths checker self-test")


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
    print("OK — every documented repository path exists")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

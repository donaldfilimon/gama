#!/usr/bin/env python3
"""Fail when a capability claim's anchor predates changes it depends on.

`docs/Capabilities.md` records, per capability, the commit whose run proved
it. Nothing checked that the claim still described the tree, so the ledger
drifted silently while every gate stayed green — twice in one day, the second
time within hours of the first being repaired by hand.

Each row carries one annotation naming its evidence layer, its anchor commit,
and the paths the claim depends on. This fails when any of those paths moved
after the anchor.

Fail-closed, in three ways that matter:
  * A row without an annotation fails. Totality is the whole point; a gate
    that tolerates unannotated rows tolerates them forever.
  * Zero parsed rows fails. A table reformat must break this loudly rather
    than quietly reduce it to checking nothing. `check-toolchain-pins.sh`
    learned this the expensive way.
  * A vocabulary term with no rule here fails. Adding a word to the document
    without teaching the gate is a failure, not a pass.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

LEDGER = "docs/Capabilities.md"
HEADER_CELL = "Capability"
ANNOTATION = re.compile(
    r"<!--\s*evidence:\s*"
    r"layer=(?P<layer>[a-z]+)\s+"
    r"anchor=(?P<anchor>[0-9a-f]{40})\s+"
    r"paths=(?P<paths>[^\s]+)\s*-->"
)
VOCABULARY_BULLET = re.compile(r"^-\s+\*\*(?P<term>[A-Za-z][A-Za-z ]*?)\*\*\s+—")

# Every derived vocabulary token needs a rule; there is deliberately no
# default branch. `unverified` is inverted on purpose: it declares that the
# claim has gone stale, so it stops being true the moment the drift is
# repaired, and a row cannot be parked there.
DRIFT_IS_FAILURE = {
    "implemented": True,
    "locally": True,
    "hosted": True,
    "provisional": True,
    "blocked": None,  # freshness not compared; anchor must still resolve
    "unverified": False,
}


def git(root: Path, *args: str) -> str:
    """Run git with --no-optional-locks; this tree is FileProvider-managed."""
    result = subprocess.run(
        ["git", "--no-optional-locks", *args],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout


def git_ok(root: Path, *args: str) -> bool:
    return (
        subprocess.run(
            ["git", "--no-optional-locks", *args],
            cwd=root,
            capture_output=True,
            check=False,
        ).returncode
        == 0
    )


def vocabulary(text: str) -> set[str]:
    """Derive allowed layer tokens from the document's own vocabulary list.

    Discovered rather than enumerated, so the two cannot drift apart.
    """
    terms = set()
    for line in text.split("\n"):
        found = VOCABULARY_BULLET.match(line.strip())
        if found:
            terms.add(found.group("term").strip().split()[0].lower())
    return terms


def rows(text: str) -> list[tuple[int, list[str]]]:
    """Return (line number, cells) for each data row of the capability table."""
    found: list[tuple[int, list[str]]] = []
    in_table = False
    for number, line in enumerate(text.split("\n"), start=1):
        stripped = line.strip()
        if not stripped.startswith("|"):
            if in_table:
                break
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if not in_table:
            if cells and cells[0] == HEADER_CELL:
                in_table = True
            continue
        if set(stripped) <= set("| -:"):
            continue
        found.append((number, cells))
    return found


def check(root: Path) -> list[str]:
    ledger = root / LEDGER
    if not ledger.is_file():
        return [f"error: {LEDGER} is missing"]
    text = ledger.read_text(encoding="utf-8")
    failures: list[str] = []

    if git(root, "rev-parse", "--is-shallow-repository").strip() == "true":
        return [
            "error: this is a shallow clone; evidence anchors are unreachable",
            "  set fetch-depth: 0 on the checkout step",
        ]

    terms = vocabulary(text)
    if len(terms) < 5:
        return [
            f"error: {LEDGER}: parsed only {len(terms)} vocabulary terms",
            "  the '## Status vocabulary' discovery pattern went stale",
        ]
    for term in sorted(terms):
        if term not in DRIFT_IS_FAILURE:
            failures.append(
                f"error: {LEDGER}: vocabulary term '{term}' has no rule in "
                "evidence-freshness.py; teach the gate before using it"
            )

    table = rows(text)
    if not table:
        return failures + [
            f"error: {LEDGER}: zero capability rows parsed; the table shape "
            "changed and this gate stopped checking anything"
        ]

    for number, cells in table:
        name = cells[0] if cells else "?"
        if len(cells) != 3:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} has {len(cells)} "
                "cells, expected 3"
            )
            continue
        matches = ANNOTATION.findall(" | ".join(cells))
        found = list(ANNOTATION.finditer(cells[2]))
        if len(matches) != 1 or len(found) != 1:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} needs exactly one "
                "evidence annotation, in its third cell"
            )
            failures.append(
                "  add: <!-- evidence: layer=<token> anchor=<40-hex> "
                "paths=<comma,separated> -->"
            )
            continue
        note = found[0]
        layer = note.group("layer")
        anchor = note.group("anchor")
        paths = note.group("paths").split(",")

        if layer not in terms:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} layer={layer} is not "
                f"a declared vocabulary term ({', '.join(sorted(terms))})"
            )
            continue

        lead = cells[1].split()[0].strip("*`").lower() if cells[1].split() else ""
        if lead != layer:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} lead word {lead!r} "
                f"does not match layer={layer}"
            )

        if paths != sorted(set(paths)):
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} paths must be sorted "
                "and deduplicated"
            )
        if LEDGER in paths:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} lists {LEDGER} as a "
                "dependency; re-anchoring would never converge"
            )
        for path in paths:
            if not path or path.startswith("/") or ".." in path:
                failures.append(
                    f"error: {LEDGER}:{number}: row {name!r} has an invalid "
                    f"path {path!r}"
                )
            elif not (root / path).exists():
                failures.append(
                    f"error: {LEDGER}:{number}: row {name!r} path {path!r} "
                    "does not exist"
                )

        if not git_ok(root, "cat-file", "-e", f"{anchor}^{{commit}}"):
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} anchor {anchor[:12]} "
                "is not in this checkout"
            )
            continue
        if not git_ok(root, "merge-base", "--is-ancestor", anchor, "HEAD"):
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} anchor {anchor[:12]} "
                "is not an ancestor of HEAD"
            )
            continue
        if anchor[:7] not in cells[1]:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} anchor {anchor[:7]} "
                "is not named in the row's prose"
            )

        rule = DRIFT_IS_FAILURE[layer]
        if rule is None:
            continue

        changed = [
            line
            for line in git(
                root, "diff", "--name-only", "--no-renames", anchor, "HEAD", "--", *paths
            ).split("\n")
            if line
        ]
        changed += [
            line
            for line in git(root, "diff", "--name-only", "HEAD", "--", *paths).split("\n")
            if line
        ]
        changed += [
            line
            for line in git(
                root, "ls-files", "--others", "--exclude-standard", "--", *paths
            ).split("\n")
            if line
        ]
        drifted = sorted(set(changed))

        if rule and drifted:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} claims layer={layer} "
                f"at {anchor[:7]} but {len(drifted)} dependency changed after "
                "that commit:"
            )
            for path in drifted[:6]:
                failures.append(f"    {path}")
            failures.append(
                "  the claim does not describe this tree. Re-anchor to a "
                "commit whose run passed, or set layer=unverified."
            )
        elif not rule and not drifted:
            failures.append(
                f"error: {LEDGER}:{number}: row {name!r} declares "
                f"layer=unverified but nothing changed since {anchor[:7]}; "
                "restore the proven layer, or correct the paths"
            )

    return failures


def self_test() -> None:
    """Prove the checker on a scratch repository outside this tree.

    Deliberately under the system temp directory: creating a git repository
    inside the iCloud-managed checkout is exactly what the project forbids.
    """
    header = (
        "# Capability evidence\n\n## Status vocabulary\n\n"
        "- **Implemented** — a\n- **Locally proven** — b\n"
        "- **Hosted proven** — c\n- **Provisional** — d\n"
        "- **Blocked** — e\n- **Unverified** — f\n\n"
        "| Capability | Current evidence | Remaining proposed/required proof |\n"
        "| --- | --- | --- |\n"
    )

    def ledger(evidence: str, remaining: str) -> str:
        return header + f"| Thing | {evidence} | {remaining} |\n"

    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        for key, value in (("user.email", "t@e.st"), ("user.name", "t")):
            subprocess.run(["git", "-C", str(root), "config", key, value], check=True)
        (root / "docs").mkdir()
        source = root / "src.swift"
        source.write_text("// one\n", encoding="utf-8")
        (root / LEDGER).write_text(ledger("Hosted proven", "none"), encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(root), "commit", "-qm", "base"], check=True)
        anchor = git(root, "rev-parse", "HEAD").strip()

        def write(layer: str, sha: str, paths: str = "src.swift") -> None:
            # The prose lead word must agree with the layer token; the
            # checker enforces that binding, so the fixture must honor it.
            note = f"<!-- evidence: layer={layer} anchor={sha} paths={paths} -->"
            (root / LEDGER).write_text(
                ledger(f"{layer.capitalize()} proven at `{sha[:7]}`", f"none {note}"),
                encoding="utf-8",
            )

        def expect(condition: bool, label: str) -> None:
            if not condition:
                raise AssertionError(f"evidence-freshness self-test: {label}")

        write("hosted", anchor)
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(root), "commit", "-qm", "annotate"], check=True)
        expect(not check(root), "a fresh row must pass")

        source.write_text("// two\n", encoding="utf-8")
        expect(any("dependency changed" in f for f in check(root)), "uncommitted drift must fail")
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(root), "commit", "-qm", "drift"], check=True)
        expect(any("dependency changed" in f for f in check(root)), "committed drift must fail")

        write("unverified", anchor)
        expect(not check(root), "unverified with real drift must pass")

        head = git(root, "rev-parse", "HEAD").strip()
        write("unverified", head)
        expect(
            any("nothing changed" in f for f in check(root)),
            "unverified without drift must fail",
        )

        write("hosted", "0" * 40)
        expect(any("not in this checkout" in f for f in check(root)), "missing anchor must fail")

        (root / LEDGER).write_text(ledger("Hosted proven", "none"), encoding="utf-8")
        expect(
            any("exactly one evidence annotation" in f for f in check(root)),
            "an unannotated row must fail",
        )

        (root / LEDGER).write_text(
            header.replace("| Capability |", "| Renamed |"), encoding="utf-8"
        )
        expect(
            any("zero capability rows" in f for f in check(root)),
            "a renamed header must fail loudly",
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        self_test()
        print("OK — evidence freshness checker self-test")

    if arguments.root is None:
        if arguments.self_test:
            return 0
        parser.error("root is required unless only --self-test is requested")

    failures = check(Path(arguments.root))
    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        return 1
    print("OK — every capability row is fresh against its anchor")
    return 0


if __name__ == "__main__":
    sys.exit(main())

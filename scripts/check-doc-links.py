#!/usr/bin/env python3
"""Fail when repository documentation contains a broken relative link."""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlsplit


INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
REFERENCE_LINK = re.compile(r"^\s*\[[^\]]+\]:\s*(\S+)")
FENCE = re.compile(r"^\s*(```|~~~)")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def markdown_files(root: Path) -> list[Path]:
    """Return the maintained Markdown surfaces in deterministic order."""
    candidates: set[Path] = set()
    for relative in ("README.md", "CONTRIBUTING.md"):
        candidate = root / relative
        if candidate.is_file():
            candidates.add(candidate)
    for relative in ("docs", "Examples"):
        directory = root / relative
        if directory.is_dir():
            candidates.update(directory.rglob("*.md"))
    sources = root / "Sources"
    if sources.is_dir():
        candidates.update(sources.glob("*/*.docc/*.md"))
    return sorted(candidates)


def remove_inline_code(line: str) -> str:
    """Remove simple inline-code spans so prose examples are not links."""
    return re.sub(r"`+[^`]*`+", "", line)


def link_targets(text: str) -> list[tuple[int, str]]:
    """Extract inline and reference-definition destinations outside fences."""
    targets: list[tuple[int, str]] = []
    in_fence = False
    fence_marker = ""
    for number, original in enumerate(text.splitlines(), start=1):
        fence = FENCE.match(original)
        if fence:
            marker = fence.group(1)
            if not in_fence:
                in_fence = True
                fence_marker = marker
            elif marker == fence_marker:
                in_fence = False
                fence_marker = ""
            continue
        if in_fence:
            continue

        line = remove_inline_code(original)
        for match in INLINE_LINK.finditer(line):
            raw = match.group(1).strip()
            if raw.startswith("<") and ">" in raw:
                raw = raw[1 : raw.index(">")]
            else:
                # Markdown permits an optional title after whitespace.
                raw = raw.split(maxsplit=1)[0]
            targets.append((number, raw))

        reference = REFERENCE_LINK.match(line)
        if reference:
            raw = reference.group(1).strip("<>")
            targets.append((number, raw))
    return targets


def relative_path_for(target: str) -> str | None:
    """Return a decoded local path, or None for non-file destinations."""
    if not target or target.startswith("#") or target.startswith("//"):
        return None
    if SCHEME.match(target):
        return None
    split = urlsplit(target)
    if split.scheme or split.netloc:
        return None
    path = unquote(split.path)
    return path or None


def check_file(root: Path, source: Path) -> list[str]:
    """Return formatted broken-link diagnostics for one Markdown file."""
    failures: list[str] = []
    text = source.read_text(encoding="utf-8")
    for line, target in link_targets(text):
        relative = relative_path_for(target)
        if relative is None:
            continue
        destination = (source.parent / relative).resolve()
        if not destination.exists():
            shown_source = source.relative_to(root)
            failures.append(f"{shown_source}:{line}: broken link: {target}")
    return failures


def check(root: Path) -> list[str]:
    failures: list[str] = []
    for source in markdown_files(root):
        failures.extend(check_file(root, source))
    return failures


def self_test() -> None:
    """Prove that valid, external, fenced, and broken cases are distinguished."""
    with tempfile.TemporaryDirectory(prefix="gama-doc-links-") as temporary:
        root = Path(temporary)
        docs = root / "docs"
        docs.mkdir()
        (root / "README.md").write_text(
            "[guide](docs/guide.md)\n[web](https://example.com)\n"
            "```md\n[example](missing-in-fence.md)\n```\n",
            encoding="utf-8",
        )
        (docs / "guide.md").write_text(
            "[root](../README.md#start)\n[missing](absent.md)\n",
            encoding="utf-8",
        )
        failures = check(root)
        expected = ["docs/guide.md:2: broken link: absent.md"]
        if failures != expected:
            raise AssertionError(f"doc-link self-test mismatch: {failures!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        self_test()
        print("OK — documentation link checker self-test")
        if arguments.root is None:
            return 0

    if arguments.root is None:
        parser.error("root is required unless only --self-test is requested")

    root = arguments.root.resolve()
    failures = check(root)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        print(f"error: {len(failures)} broken documentation link(s)", file=sys.stderr)
        return 1
    print(f"OK — relative links across {len(markdown_files(root))} Markdown files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

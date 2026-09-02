#!/usr/bin/env python3
"""Enforce GamaWASM's single, private nonisolated(unsafe) storage slot."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Mapping


UNSAFE = re.compile(r"\bnonisolated[ \t]*\([ \t]*unsafe[ \t]*\)")
INSTALLED_SLOT = re.compile(
    r"(?m)^[ \t]*private[ \t]+nonisolated[ \t]*\([ \t]*unsafe[ \t]*\)"
    r"[ \t]+static[ \t]+var[ \t]+installed[ \t]*:[ \t]*"
    r"\(any[ \t]+AnyWASMHost\)[ \t]*\?[ \t]*$"
)


def strip_comments_and_strings(source: str) -> str:
    """Replace Swift comments and string literals with whitespace.

    Newlines are retained so diagnostics still name the original line. Swift
    block comments may nest, and raw strings use matching `#` delimiters.
    String interpolation is intentionally blanked with the surrounding prose:
    declarations cannot live inside a string literal.
    """

    output = list(source)
    index = 0
    length = len(source)

    def blank(start: int, end: int) -> None:
        for position in range(start, end):
            if output[position] not in "\r\n":
                output[position] = " "

    while index < length:
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            if end == -1:
                end = length
            blank(index, end)
            index = end
            continue

        if source.startswith("/*", index):
            start = index
            depth = 1
            index += 2
            while index < length and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            blank(start, index)
            continue

        raw_hashes = 0
        while index + raw_hashes < length and source[index + raw_hashes] == "#":
            raw_hashes += 1
        quote_index = index + raw_hashes
        if quote_index < length and source[quote_index] == '"':
            start = index
            triple = source.startswith('\"\"\"', quote_index)
            quote_count = 3 if triple else 1
            closing = ('"' * quote_count) + ('#' * raw_hashes)
            index = quote_index + quote_count
            while index < length:
                if source.startswith(closing, index):
                    index += len(closing)
                    break
                if raw_hashes == 0 and not triple and source[index] == "\\":
                    index = min(length, index + 2)
                else:
                    index += 1
            blank(start, index)
            continue

        index += 1

    return "".join(output)


def validate_sources(sources: Mapping[str, str]) -> list[str]:
    unsafe_occurrences: list[tuple[str, int]] = []
    installed_slots: list[tuple[str, int]] = []

    for name, source in sorted(sources.items()):
        code = strip_comments_and_strings(source)
        for match in UNSAFE.finditer(code):
            unsafe_occurrences.append((name, code.count("\n", 0, match.start()) + 1))
        for match in INSTALLED_SLOT.finditer(code):
            installed_slots.append((name, code.count("\n", 0, match.start()) + 1))

    errors: list[str] = []
    if len(unsafe_occurrences) != 1:
        rendered = ", ".join(f"{name}:{line}" for name, line in unsafe_occurrences)
        errors.append(
            "expected exactly one Swift nonisolated(unsafe) declaration under "
            f"Sources/GamaWASM; found {len(unsafe_occurrences)}"
            + (f" at {rendered}" if rendered else "")
        )
    if len(installed_slots) != 1:
        rendered = ", ".join(f"{name}:{line}" for name, line in installed_slots)
        errors.append(
            "the sole unsafe declaration must be exactly "
            "`private nonisolated(unsafe) static var installed: (any AnyWASMHost)?`; "
            f"found {len(installed_slots)} matching slot declarations"
            + (f" at {rendered}" if rendered else "")
        )
    if unsafe_occurrences and installed_slots and unsafe_occurrences != installed_slots:
        errors.append("the unsafe declaration and the private installed-host slot differ")
    return errors


def run_self_test() -> None:
    valid = {
        "WASMHost.swift": """
// nonisolated(unsafe) prose must not count.
let prose = "nonisolated(unsafe) static var decoy"
/* nested /* nonisolated(unsafe) */ comment */
private nonisolated(unsafe) static var installed: (any AnyWASMHost)?
""",
    }
    cases = {
        "valid": (valid, True),
        "removed": ({"WASMHost.swift": "private static var installed: Int?"}, False),
        "renamed": (
            {
                "WASMHost.swift":
                    "private nonisolated(unsafe) static var current: (any AnyWASMHost)?"
            },
            False,
        ),
        "widened": (
            {
                "WASMHost.swift":
                    "nonisolated(unsafe) static var installed: (any AnyWASMHost)?"
            },
            False,
        ),
        "duplicate": (
            {
                "WASMHost.swift": valid["WASMHost.swift"]
                    + "\nprivate nonisolated(unsafe) static var second: Int?\n"
            },
            False,
        ),
        "comments-only": (
            {"WASMHost.swift": "// nonisolated(unsafe)\n/* nonisolated(unsafe) */"},
            False,
        ),
    }
    for name, (sources, should_pass) in cases.items():
        passed = not validate_sources(sources)
        if passed != should_pass:
            raise AssertionError(f"self-test {name!r} produced passed={passed}")


def load_swift_sources(root: Path) -> dict[str, str]:
    if not root.is_dir():
        raise ValueError(f"Swift source root is missing: {root}")
    files = sorted(root.rglob("*.swift"))
    if not files:
        raise ValueError(f"no Swift sources found under: {root}")
    return {
        str(path.relative_to(root)): path.read_text(encoding="utf-8")
        for path in files
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_root", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        run_self_test()
        print("OK — WASM unsafe-declaration scanner mutation tests")
    if arguments.source_root is None:
        if arguments.self_test:
            return 0
        parser.error("source_root is required unless --self-test is used")

    try:
        errors = validate_sources(load_swift_sources(arguments.source_root))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print("OK — GamaWASM has exactly one private installed-host unsafe slot")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

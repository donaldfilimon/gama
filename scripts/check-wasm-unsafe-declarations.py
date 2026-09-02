#!/usr/bin/env python3
"""Enforce GamaWASM's single, private nonisolated(unsafe) storage slot."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


UNSAFE_TOKENS = ("nonisolated", "(", "unsafe", ")")
INSTALLED_SLOT_TOKENS = (
    "private",
    "nonisolated",
    "(",
    "unsafe",
    ")",
    "static",
    "var",
    "installed",
    ":",
    "(",
    "any",
    "AnyWASMHost",
    ")",
    "?",
)


@dataclass(frozen=True)
class Token:
    value: str
    kind: str
    line: int
    offset: int
    interpolation_depth: int


class SwiftLexer:
    """Small policy lexer for Swift declarations in every `#if` branch.

    The gate deliberately does not use the type-checked AST: the host compiler
    drops inactive wasm32 branches. This lexer retains all conditional source,
    removes comments and literal prose, and recursively tokenizes executable
    string/regex interpolation expressions.
    """

    REGEX_PREFIX_VALUES = {
        "=",
        "(",
        "[",
        "{",
        ",",
        ":",
        ";",
        "!",
        "?",
        "return",
        "throw",
        "case",
        "in",
        "where",
    }

    def __init__(self, source: str) -> None:
        self.source = source
        self.index = 0
        self.line = 1
        self.interpolation_depth = 0
        self.tokens: list[Token] = []

    def scan(self) -> list[Token]:
        self._scan_code()
        return self.tokens

    def _advance(self, count: int = 1) -> None:
        text = self.source[self.index : self.index + count]
        self.line += text.count("\n")
        self.index += count

    def _emit(self, value: str, kind: str, line: int, offset: int) -> None:
        self.tokens.append(
            Token(value, kind, line, offset, self.interpolation_depth)
        )

    def _emit_boundary(self, label: str) -> None:
        self._emit(label, "literal-boundary", self.line, self.index)

    def _scan_code(self, interpolation_parentheses: int | None = None) -> None:
        length = len(self.source)
        parentheses = interpolation_parentheses

        while self.index < length:
            if self.source.startswith("//", self.index):
                self._skip_line_comment()
                continue
            if self.source.startswith("/*", self.index):
                self._skip_block_comment()
                continue

            literal = self._literal_prefix()
            if literal is not None:
                kind, hashes, delimiter_width = literal
                if kind == "string":
                    self._scan_string(hashes, delimiter_width)
                else:
                    self._scan_regex(hashes)
                continue

            character = self.source[self.index]
            if character.isspace():
                self._advance()
                continue

            if character == "/" and self._can_start_bare_regex():
                self._scan_regex(0)
                continue

            if character == "`":
                self._scan_escaped_identifier()
                continue

            if character == "_" or character.isalpha():
                self._scan_identifier()
                continue

            if character.isdigit():
                self._scan_number()
                continue

            start_line = self.line
            start_offset = self.index
            self._advance()
            if parentheses is not None and character == "(":
                parentheses += 1
            elif parentheses is not None and character == ")":
                parentheses -= 1
                if parentheses == 0:
                    return
            self._emit(character, "punctuation", start_line, start_offset)

    def _skip_line_comment(self) -> None:
        newline = self.source.find("\n", self.index + 2)
        end = len(self.source) if newline == -1 else newline
        self._advance(end - self.index)

    def _skip_block_comment(self) -> None:
        depth = 1
        self._advance(2)
        while self.index < len(self.source) and depth:
            if self.source.startswith("/*", self.index):
                depth += 1
                self._advance(2)
            elif self.source.startswith("*/", self.index):
                depth -= 1
                self._advance(2)
            else:
                self._advance()

    def _literal_prefix(self) -> tuple[str, int, int] | None:
        cursor = self.index
        hashes = 0
        while cursor < len(self.source) and self.source[cursor] == "#":
            hashes += 1
            cursor += 1

        if self.source.startswith('"""', cursor):
            return ("string", hashes, 3)
        if cursor < len(self.source) and self.source[cursor] == '"':
            return ("string", hashes, 1)
        if hashes and cursor < len(self.source) and self.source[cursor] == "/":
            return ("regex", hashes, 1)
        return None

    def _scan_interpolation(self, hashes: int) -> bool:
        opener = "\\" + ("#" * hashes) + "("
        if not self.source.startswith(opener, self.index):
            return False

        self._emit_boundary("<interpolation-start>")
        self._advance(len(opener))
        self.interpolation_depth += 1
        self._scan_code(interpolation_parentheses=1)
        self.interpolation_depth -= 1
        self._emit_boundary("<interpolation-end>")
        return True

    def _scan_string(self, hashes: int, quote_width: int) -> None:
        self._emit_boundary("<string-start>")
        self._advance(hashes + quote_width)
        closing = ('"' * quote_width) + ("#" * hashes)

        while self.index < len(self.source):
            if self.source.startswith(closing, self.index):
                self._advance(len(closing))
                self._emit_boundary("<string-end>")
                return
            if self._scan_interpolation(hashes):
                continue
            if self.source[self.index] == "\\":
                escape = "\\" + ("#" * hashes)
                if self.source.startswith(escape, self.index):
                    remaining = len(escape)
                    if self.index + remaining < len(self.source):
                        remaining += 1
                    self._advance(remaining)
                else:
                    self._advance()
                continue
            self._advance()

        self._emit_boundary("<unterminated-string>")

    def _can_start_bare_regex(self) -> bool:
        if self.source.startswith("//", self.index) or self.source.startswith(
            "/*", self.index
        ):
            return False
        if not self.tokens:
            return True
        previous = self.tokens[-1]
        return previous.value in self.REGEX_PREFIX_VALUES

    def _scan_regex(self, hashes: int) -> None:
        self._emit_boundary("<regex-start>")
        self._advance(hashes + 1)
        closing = "/" + ("#" * hashes)
        character_class_depth = 0

        while self.index < len(self.source):
            if character_class_depth == 0 and self.source.startswith(
                closing, self.index
            ):
                self._advance(len(closing))
                self._emit_boundary("<regex-end>")
                return
            if self._scan_interpolation(hashes):
                continue
            character = self.source[self.index]
            if character == "[":
                character_class_depth += 1
                self._advance()
                continue
            if character == "]" and character_class_depth:
                character_class_depth -= 1
                self._advance()
                continue
            if character == "\\":
                escape = "\\" + ("#" * hashes)
                if self.source.startswith(escape, self.index):
                    remaining = len(escape)
                    if self.index + remaining < len(self.source):
                        remaining += 1
                    self._advance(remaining)
                else:
                    self._advance()
                continue
            self._advance()

        self._emit_boundary("<unterminated-regex>")

    def _scan_escaped_identifier(self) -> None:
        start_line = self.line
        start_offset = self.index
        self._advance()
        value_start = self.index
        while self.index < len(self.source) and self.source[self.index] != "`":
            self._advance()
        value = self.source[value_start : self.index]
        if self.index < len(self.source):
            self._advance()
        self._emit(value, "escaped-identifier", start_line, start_offset)

    def _scan_identifier(self) -> None:
        start_line = self.line
        start_offset = self.index
        self._advance()
        while self.index < len(self.source):
            character = self.source[self.index]
            if character != "_" and not character.isalnum():
                break
            self._advance()
        self._emit(
            self.source[start_offset : self.index],
            "identifier",
            start_line,
            start_offset,
        )

    def _scan_number(self) -> None:
        start_line = self.line
        start_offset = self.index
        self._advance()
        while self.index < len(self.source):
            character = self.source[self.index]
            if character != "_" and not character.isalnum() and character != ".":
                break
            self._advance()
        self._emit("<number>", "literal", start_line, start_offset)


def token_sequence_at(tokens: list[Token], index: int, values: tuple[str, ...]) -> bool:
    candidate = tokens[index : index + len(values)]
    if len(candidate) != len(values):
        return False
    return all(
        token.value == value and token.kind != "escaped-identifier"
        for token, value in zip(candidate, values, strict=True)
    )


def direct_enclosing_scope_is_gama_web(tokens: list[Token], index: int) -> bool:
    """Require the slot to be a direct member of `enum GamaWeb`."""

    visible = [
        token
        for token in tokens[:index]
        if token.interpolation_depth == 0
        and token.kind != "literal-boundary"
    ]
    braces: list[int] = []
    for position, token in enumerate(visible):
        if token.value == "{":
            braces.append(position)
        elif token.value == "}" and braces:
            braces.pop()
    if not braces:
        return False

    opening = braces[-1]
    header_start = opening - 1
    while header_start >= 0 and visible[header_start].value not in {"{", "}", ";"}:
        header_start -= 1
    header = visible[header_start + 1 : opening]
    for position in range(len(header) - 1):
        if (
            header[position].value == "enum"
            and header[position + 1].value == "GamaWeb"
            and header[position + 1].kind != "escaped-identifier"
        ):
            return True
    return False


def is_installed_slot(name: str, tokens: list[Token], unsafe_index: int) -> bool:
    start = unsafe_index - 1
    if name != "WASMHost.swift" or start < 0:
        return False
    if not token_sequence_at(tokens, start, INSTALLED_SLOT_TOKENS):
        return False

    candidate = tokens[start : start + len(INSTALLED_SLOT_TOKENS)]
    if any(token.interpolation_depth != 0 for token in candidate):
        return False
    if not direct_enclosing_scope_is_gama_web(tokens, start):
        return False

    following = start + len(INSTALLED_SLOT_TOKENS)
    while following < len(tokens) and tokens[following].kind == "literal-boundary":
        following += 1
    if following < len(tokens) and tokens[following].value in {"=", "{"}:
        return False
    return True


def validate_sources(sources: Mapping[str, str]) -> list[str]:
    unsafe_occurrences: list[tuple[str, int]] = []
    installed_slots: list[tuple[str, int]] = []

    for name, source in sorted(sources.items()):
        tokens = SwiftLexer(source).scan()
        for index in range(len(tokens)):
            if not token_sequence_at(tokens, index, UNSAFE_TOKENS):
                continue
            occurrence = (name, tokens[index].line)
            unsafe_occurrences.append(occurrence)
            if is_installed_slot(name, tokens, index):
                installed_slots.append(occurrence)

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
            "the sole unsafe declaration must be the direct GamaWeb member "
            "`private nonisolated(unsafe) static var installed: "
            "(any AnyWASMHost)?` in WASMHost.swift; "
            f"found {len(installed_slots)} matching slot declarations"
            + (f" at {rendered}" if rendered else "")
        )
    if unsafe_occurrences and installed_slots and unsafe_occurrences != installed_slots:
        errors.append("the unsafe declaration and the private installed-host slot differ")
    return errors


def run_self_test() -> None:
    canonical = """
public enum GamaWeb {
    // nonisolated(unsafe) prose must not count.
    let prose = "nonisolated(unsafe) static var decoy"
    /* nested /* nonisolated(unsafe) */ comment */
    private nonisolated(unsafe) static var installed: (any AnyWASMHost)?
}
"""
    multiline_slot = """
public enum GamaWeb {
    private
    nonisolated(
        unsafe
    )
    static var installed:
        (any AnyWASMHost)?
}
"""
    cases = {
        "valid": ({"WASMHost.swift": canonical}, True),
        "valid-multiline-slot": ({"WASMHost.swift": multiline_slot}, True),
        "removed": (
            {"WASMHost.swift": "public enum GamaWeb { private static var installed: Int? }"},
            False,
        ),
        "renamed": (
            {
                "WASMHost.swift": canonical.replace(
                    "static var installed", "static var current"
                )
            },
            False,
        ),
        "widened": (
            {"WASMHost.swift": canonical.replace("    private nonisolated", "    nonisolated")},
            False,
        ),
        "duplicate": (
            {
                "WASMHost.swift": canonical.replace(
                    "\n}",
                    "\n    private nonisolated(unsafe) static var second: Int?\n}",
                )
            },
            False,
        ),
        "multiline-extra": (
            {
                "WASMHost.swift": canonical
                + """
struct Extra {
    nonisolated(
        unsafe
    ) static var hidden = 0
}
"""
            },
            False,
        ),
        "interpolation-extra": (
            {
                "WASMHost.swift": canonical
                + r'''
let text = "\({ struct Hidden { nonisolated(unsafe) static var hidden = 0 }; return "" }())"
'''
            },
            False,
        ),
        "raw-interpolation-extra": (
            {
                "WASMHost.swift": canonical
                + r'''
let text = #"\#({ struct Hidden { nonisolated(unsafe) static var hidden = 0 }; return "" }())"#
'''
            },
            False,
        ),
        "regex-and-backticks-are-not-declarations": (
            {
                "WASMHost.swift": canonical
                + r'''
let rawPattern = #/nonisolated(unsafe)/#
let barePattern = /nonisolated(unsafe)/
func `nonisolated`(_ value: Int) {}
`nonisolated`(0)
'''
            },
            True,
        ),
        "comments-only": (
            {"WASMHost.swift": "// nonisolated(unsafe)\n/* nonisolated(unsafe) */"},
            False,
        ),
        "wrong-file": ({"Other.swift": canonical}, False),
        "wrong-scope": (
            {
                "WASMHost.swift": canonical.replace(
                    "public enum GamaWeb", "private enum Other"
                )
            },
            False,
        ),
    }
    for name, (sources, should_pass) in cases.items():
        passed = not validate_sources(sources)
        if passed != should_pass:
            errors = validate_sources(sources)
            raise AssertionError(
                f"self-test {name!r} produced passed={passed}, errors={errors}"
            )


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

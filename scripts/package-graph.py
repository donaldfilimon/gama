#!/usr/bin/env python3
"""Assert the manifest properties that ADRs claim but nothing checked.

Three settled decisions lived only in `Package.swift`'s per-target argument
lists, where a new target simply omitting them was silently conforming:

  * ADR 0012 — strict memory safety, with `StrictMemorySafety` promoted to an
    error, on every shipped library and macro target. It was hand-attached
    thirteen times; a fourteenth target that forgot escaped the ADR entirely
    while `docs/Capabilities.md` kept claiming "every shipped library".
  * The zero-runtime-dependency guarantee — swift-syntax is build-time only,
    so no shipped library may reach a package product. Nothing inspected the
    dependency graph.
  * `Extern` is experimental and scoped to `GamaWASM`; and ADR 0012 decision 4
    bans `NonisolatedNonsendingByDefault` outright.

The strict-scope exemption is derived, not listed: a target is exempt only if
it has no Swift sources on disk. `GamaEmbedABI` and `GamaTUISignal` are C-only
today, and a name-based allowlist would have let a Swift file appear in one of
them without notice.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Only GamaWASM may enable Extern; see docs/Toolchain.md.
EXTERN_TARGET = "GamaWASM"
# ADR 0012 decision 4: assess, do not assume.
BANNED_FEATURES = {"NonisolatedNonsendingByDefault"}
# Build-time-only target kinds may reach a package product.
MAY_USE_PRODUCTS = {"macro", "test"}
SHIPPED_KINDS = {"regular", "macro"}


def settings(target: dict) -> list[tuple[str, object]]:
    """Flatten a target's swiftSettings into (kind, payload) pairs."""
    out: list[tuple[str, object]] = []
    for setting in target.get("settings", []):
        for kind, payload in setting.get("kind", {}).items():
            out.append((kind, payload))
    return out


def has_strict_memory_safety(target: dict) -> bool:
    return any(kind == "strictMemorySafety" for kind, _ in settings(target))


def promotes_strict_to_error(target: dict) -> bool:
    for kind, payload in settings(target):
        if kind != "treatWarning" or not isinstance(payload, dict):
            continue
        if payload.get("_0") == "StrictMemorySafety" and payload.get("_1") == "error":
            return True
    return False


def features(target: dict) -> set[str]:
    found: set[str] = set()
    for kind, payload in settings(target):
        if kind in ("enableExperimentalFeature", "enableUpcomingFeature"):
            if isinstance(payload, dict):
                found.add(str(payload.get("_0")))
    return found


def product_dependencies(target: dict) -> list[str]:
    names: list[str] = []
    for dep in target.get("dependencies", []):
        product = dep.get("product")
        if isinstance(product, list) and product:
            names.append(str(product[0]))
        elif isinstance(product, dict):
            names.append(str(product.get("_0")))
    return names


def has_swift_sources(root: Path, target: dict) -> bool:
    """True when the target has any .swift file on disk.

    Derived rather than declared: this is what makes the strict-memory-safety
    exemption self-correcting when a C-only target gains Swift.
    """
    path = target.get("path") or f"Sources/{target['name']}"
    directory = root / path
    if not directory.is_dir():
        # Cannot see the sources, so cannot justify an exemption.
        return True
    return any(directory.rglob("*.swift"))


def check(root: Path, manifest: dict) -> list[str]:
    failures: list[str] = []
    targets = manifest.get("targets", [])
    if not targets:
        return ["error: dump-package returned no targets; this gate checked nothing"]

    shipped = 0
    for target in sorted(targets, key=lambda t: t["name"]):
        name = target["name"]
        kind = target.get("type", "")

        if kind in SHIPPED_KINDS:
            if has_swift_sources(root, target):
                shipped += 1
                if not has_strict_memory_safety(target):
                    failures.append(
                        f"error: shipped target {name!r} does not enable "
                        "strictMemorySafety (ADR 0012)"
                    )
                if not promotes_strict_to_error(target):
                    failures.append(
                        f"error: shipped target {name!r} does not promote "
                        "StrictMemorySafety to an error (ADR 0012)"
                    )
            # A target with no Swift sources is exempt by derivation, not by
            # name. If it ever gains a .swift file it stops being exempt.

        if kind == "regular":
            products = product_dependencies(target)
            if products:
                failures.append(
                    f"error: shipped library {name!r} depends on package "
                    f"product(s) {', '.join(products)}; shipped products must "
                    "retain zero runtime package dependencies"
                )
        elif kind not in MAY_USE_PRODUCTS and product_dependencies(target):
            failures.append(
                f"error: target {name!r} ({kind}) depends on a package product"
            )

        enabled = features(target)
        for banned in sorted(enabled & BANNED_FEATURES):
            failures.append(
                f"error: target {name!r} enables {banned}, which ADR 0012 "
                "decision 4 bans"
            )
        if "Extern" in enabled and name != EXTERN_TARGET:
            failures.append(
                f"error: target {name!r} enables the experimental Extern "
                f"feature, which is scoped to {EXTERN_TARGET} only"
            )

    if shipped == 0:
        failures.append(
            "error: no shipped Swift target was inspected; the manifest shape "
            "changed and this gate stopped checking anything"
        )
    return failures


def self_test() -> None:
    """Prove each predicate against synthetic manifests."""
    strict = {
        "name": "T",
        "type": "regular",
        "settings": [
            {"kind": {"strictMemorySafety": {}}},
            {"kind": {"treatWarning": {"_0": "StrictMemorySafety", "_1": "error"}}},
        ],
    }
    assert has_strict_memory_safety(strict)
    assert promotes_strict_to_error(strict)

    warn_only = {
        "name": "T",
        "type": "regular",
        "settings": [
            {"kind": {"strictMemorySafety": {}}},
            {"kind": {"treatWarning": {"_0": "StrictMemorySafety", "_1": "warning"}}},
        ],
    }
    assert not promotes_strict_to_error(warn_only), "warning must not count as error"

    assert features({"settings": [{"kind": {"enableExperimentalFeature": {"_0": "Extern"}}}]}) == {
        "Extern"
    }
    assert product_dependencies(
        {"dependencies": [{"product": ["SwiftSyntaxMacros", "swift-syntax", None, None]}]}
    ) == ["SwiftSyntaxMacros"]
    assert product_dependencies({"dependencies": [{"byName": ["GamaCore", None]}]}) == []
    assert check(Path("/nonexistent"), {"targets": []})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?")
    parser.add_argument("--manifest", help="pre-dumped JSON; otherwise dump-package runs")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        self_test()
        print("OK — package graph checker self-test")
    if arguments.root is None:
        if arguments.self_test:
            return 0
        parser.error("root is required unless only --self-test is requested")

    root = Path(arguments.root)
    if arguments.manifest:
        manifest = json.loads(Path(arguments.manifest).read_text(encoding="utf-8"))
    else:
        dumped = subprocess.run(
            ["swift", "package", "--package-path", str(root), "dump-package"],
            capture_output=True,
            text=True,
            check=False,
        )
        if dumped.returncode != 0:
            print("error: swift package dump-package failed", file=sys.stderr)
            print(dumped.stderr[:2000], file=sys.stderr)
            return 1
        manifest = json.loads(dumped.stdout)

    failures = check(root, manifest)
    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        return 1
    print(
        "OK — strict memory safety on every shipped Swift target, zero runtime "
        "package dependencies, and scoped experimental features"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

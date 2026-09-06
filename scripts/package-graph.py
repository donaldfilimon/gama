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
  * ADR 0012's *other* half: `ExistentialAny`, `MemberImportVisibility`, and
    `InternalImportsByDefault` on every Swift target. The record pairs strict
    memory safety with "explicit import access levels everywhere", and only the
    first was checked here. Both live in `Package.swift` helper arrays, so a
    target assembling its own settings list keeps one promise and drops the
    other with nothing to say so.
  * Swift 6 language mode on every Swift target. Added 2026-09-06 because a
    second gate came to depend on it: `scripts/portable-global-state.py`
    polices only the two hatches around process-global state
    (`nonisolated(unsafe)` and global-actor isolation) on the measured ground
    that the language mode rejects the bare case by itself — planting
    `static var probeCounter = 0` in `GamaPlugin` fails with "nonisolated
    global shared mutable state". `swiftLanguageVersions` is unset
    package-wide, so the mode is hand-attached per target exactly like the
    settings above; dropping one target to Swift 5 would silently reopen bare
    mutable globals there while every gate stayed green.

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
# Swift 6 mode is the ground scripts/portable-global-state.py stands on.
REQUIRED_LANGUAGE_MODE = "6"
# ADR 0012 has two halves and only strict memory safety was checked. These are
# the other half — "explicit import access levels everywhere" — and they live in
# `strictCore`, which every Swift target takes directly or through
# `strictLibrary`. A new target with a hand-rolled settings list would keep the
# memory-safety promise and silently drop this one.
REQUIRED_UPCOMING_FEATURES = frozenset(
    {"ExistentialAny", "MemberImportVisibility", "InternalImportsByDefault"}
)


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


def swift_language_modes(target: dict) -> list[str]:
    """Every Swift language mode the target declares, in manifest order.

    A list rather than the first match, because a target can declare the
    setting twice and the LAST one wins at compile time. Measured 2026-09-06:
    `strictLibrary + [.swiftLanguageMode(.v5)]` on `GamaPlugin` dumps as
    `[{"_0": "6"}, {"_0": "5"}]`, and a bare `static var probeCounter = 0`
    then compiles with zero concurrency errors — the hatch
    `scripts/portable-global-state.py` relies on being shut. A first-match
    accessor read "6" off that manifest and passed, which is exactly the
    false green this gate exists to prevent, so every declared mode is
    checked and any non-6 fails.
    """
    found: list[str] = []
    for kind, payload in settings(target):
        if kind != "swiftLanguageMode":
            continue
        found.append(str(payload.get("_0")) if isinstance(payload, dict) else str(payload))
    return found


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
    swift_targets = 0
    for target in sorted(targets, key=lambda t: t["name"]):
        name = target["name"]
        kind = target.get("type", "")
        swift = has_swift_sources(root, target)

        # Every Swift target, not only the shipped ones: the language-mode
        # guarantee is per-module, and an executable or the test target
        # dropping to Swift 5 reopens bare mutable globals just as quietly.
        if swift:
            swift_targets += 1
            modes = swift_language_modes(target)
            offenders = [m for m in modes if m != REQUIRED_LANGUAGE_MODE]
            if not modes or offenders:
                declared = ", ".join(repr(m) for m in modes) or "none"
                failures.append(
                    f"error: Swift target {name!r} declares language mode(s) "
                    f"{declared}, and every one must be "
                    f"{REQUIRED_LANGUAGE_MODE!r}; the last declaration wins at "
                    "compile time, and scripts/portable-global-state.py "
                    "polices only the two hatches around process-global state "
                    "because Swift 6 mode rejects the bare case itself"
                )
            absent = REQUIRED_UPCOMING_FEATURES - features(target)
            if absent:
                failures.append(
                    f"error: Swift target {name!r} does not enable "
                    f"{', '.join(sorted(absent))}; ADR 0012 requires explicit "
                    "import access levels on every Swift target, not only the "
                    "shipped ones it also holds to strict memory safety"
                )

        if kind in SHIPPED_KINDS:
            if swift:
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
    if swift_targets == 0:
        failures.append(
            "error: no Swift target was language-mode checked; the manifest "
            "shape changed and this gate stopped checking anything"
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

    # Language mode: the real dump spells it {"_0": "6"}. A target that sets
    # none, or sets 5, must be caught — those are the two shapes that would
    # reopen bare mutable globals under scripts/portable-global-state.py.
    assert swift_language_modes(strict) == [], "no mode declared must read as []"
    v6 = {"kind": {"swiftLanguageMode": {"_0": "6"}}}
    v5 = {"kind": {"swiftLanguageMode": {"_0": "5"}}}
    assert swift_language_modes({"settings": [v6]}) == ["6"]
    assert swift_language_modes({"settings": [v5]}) == ["5"]
    # The measured shape of `strictLibrary + [.swiftLanguageMode(.v5)]`. A
    # first-match accessor reads "6" here and passes while the compiler uses 5.
    assert swift_language_modes({"settings": [v6, v5]}) == ["6", "5"]

    assert features({"settings": [{"kind": {"enableExperimentalFeature": {"_0": "Extern"}}}]}) == {
        "Extern"
    }
    assert product_dependencies(
        {"dependencies": [{"product": ["SwiftSyntaxMacros", "swift-syntax", None, None]}]}
    ) == ["SwiftSyntaxMacros"]
    assert product_dependencies({"dependencies": [{"byName": ["GamaCore", None]}]}) == []
    assert check(Path("/nonexistent"), {"targets": []})

    # End to end on a synthetic manifest, since has_swift_sources() treats an
    # unreadable directory as "has Swift" and therefore in scope: a v6 target
    # is clean on the language-mode rule, a v5 target is not, and a target
    # declaring no mode at all is not either.
    def modes_reported(mode_setting: list) -> list[str]:
        target = {
            "name": "Probe",
            "type": "regular",
            "settings": [
                {"kind": {"strictMemorySafety": {}}},
                {"kind": {"treatWarning": {"_0": "StrictMemorySafety", "_1": "error"}}},
            ]
            + mode_setting,
        }
        return [f for f in check(Path("/nonexistent"), {"targets": [target]})
                if "language mode" in f]

    assert modes_reported([v6]) == [], modes_reported([v6])
    assert len(modes_reported([v5])) == 1, "Swift 5 mode must fail"
    assert len(modes_reported([])) == 1, "an undeclared mode must fail"
    # ADR 0012's upcoming-feature half.
    def features_reported(names: list[str]) -> list[str]:
        target = {
            "name": "Probe",
            "type": "regular",
            "settings": [
                {"kind": {"strictMemorySafety": {}}},
                {"kind": {"treatWarning": {"_0": "StrictMemorySafety", "_1": "error"}}},
                v6,
            ]
            + [{"kind": {"enableUpcomingFeature": {"_0": n}}} for n in names],
        }
        return [f for f in check(Path("/nonexistent"), {"targets": [target]})
                if "import access levels" in f]

    assert features_reported(sorted(REQUIRED_UPCOMING_FEATURES)) == []
    assert len(features_reported([])) == 1, "no upcoming features must fail"
    partial = features_reported(["ExistentialAny"])
    assert len(partial) == 1 and "MemberImportVisibility" in partial[0], partial
    assert "ExistentialAny" not in partial[0], "only the absent ones are named"

    assert len(modes_reported([v6, v5])) == 1, (
        "v6 followed by v5 is the real regression shape and must fail; the "
        "last declaration is the one the compiler uses"
    )


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
        "OK — Swift 6 language mode and explicit import access levels on every "
        "Swift target, strict memory safety on every shipped one, zero runtime "
        "package dependencies, and scoped experimental features"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

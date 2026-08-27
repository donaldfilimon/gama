#!/usr/bin/env python3
"""Doc-comment coverage over SwiftPM symbol graphs.

Reads every Gama-module *.symbols.json produced by `swift package
dump-symbol-graph --minimum-access-level public`, and fails when a public
symbol has no doc comment, is not inherited (`origin` absent), and is not
allowlisted. Deterministic: pinned toolchain upstream, sorted output,
path-keyed identifiers.
"""
import json
import os
import sys
import glob


def load_allowlist(path):
    allowed = set()
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#"):
                allowed.add(line)
    return allowed


def main():
    if len(sys.argv) != 3:
        print("usage: doc-coverage.py <scratch-dir> <allowlist>", file=sys.stderr)
        return 2
    scratch, allowlist_path = sys.argv[1], sys.argv[2]
    allowed = load_allowlist(allowlist_path)

    graphs = []
    for p in glob.glob(os.path.join(scratch, "**", "*.symbols.json"), recursive=True):
        name = os.path.basename(p)
        if "@" in name:  # cross-module extension graph — not this module's API
            continue
        if not name.startswith("Gama") and not name.startswith("gama"):
            continue
        graphs.append(p)
    if not graphs:
        print("error: no Gama symbol graphs found under " + scratch, file=sys.stderr)
        return 2

    missing = []
    for p in sorted(graphs):
        data = json.load(open(p, encoding="utf-8"))
        module = data.get("module", {}).get("name", os.path.basename(p))
        for sym in data.get("symbols", []):
            if "origin" in sym:  # inherited/synthesized from a protocol requirement
                continue
            if sym.get("docComment"):
                continue
            # Only audit symbols declared in this module's own sources:
            # @_exported re-exports and protocol-default members surface in
            # the graph without doc comments but are not this module's debt.
            uri = sym.get("location", {}).get("uri", "")
            if "/Sources/%s/" % module not in uri:
                continue
            path_components = sym.get("pathComponents", [])
            ident = module + "." + ".".join(path_components)
            if ident in allowed:
                continue
            kind = sym.get("kind", {}).get("identifier", "?")
            missing.append((module, ident, kind))

    if missing:
        print(
            "error: %d public declarations lack documentation (see %s)"
            % (len(missing), os.path.basename(allowlist_path)),
            file=sys.stderr,
        )
        for module, ident, kind in sorted(set(missing)):
            print("%s  %s  (%s)" % (module, ident, kind), file=sys.stderr)
        return 1
    print("OK — every public declaration in every Gama module is documented")
    return 0


if __name__ == "__main__":
    sys.exit(main())

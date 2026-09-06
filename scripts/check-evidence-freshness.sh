#!/usr/bin/env bash
# Fail when a capability claim in docs/Capabilities.md is anchored to a commit
# that predates changes to the files the claim depends on.
#
# NOT yet in the gates=(...) array of scripts/check.sh. Turning it on requires
# annotating every row in one commit: a partially annotated table cannot be
# fail-closed on totality, and a gate that tolerates unannotated rows for a
# few weeks tolerates them permanently.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/evidence-freshness.py" --self-test "$ROOT"

#!/usr/bin/env bash
# Fail when a capability claim in docs/Capabilities.md is anchored to a commit
# that predates changes to the files the claim depends on.
#
# The fourteenth gate in scripts/check.sh. Every row was annotated in one
# commit rather than in batches: a partially annotated table cannot be
# fail-closed on totality, and a gate that tolerates unannotated rows for a
# few weeks tolerates them permanently.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/evidence-freshness.py" --self-test "$ROOT"

# Testing catalog rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Name `ActionIdentityTests.swift` and `TerminalCapabilityTests.swift` in the suite table in `docs/Testing.md`.

**Architecture:** `docs/Testing.md` says every suite lives in `Tests/gamaTests/` and then lists those files in one table. The two files exist on disk and are absent from that table. The fix is two rows. No production type changes.

**Tech Stack:** The catalog is Markdown. The check is a short Python comparison of filenames. It does not build the package.

---

### Task 1: Add the two missing rows

**Files:**
- Modify: `docs/Testing.md` (the suite table under `## Layout`)
- Read: `Tests/gamaTests/ActionIdentityTests.swift` (`@Suite("Action identity")`)
- Read: `Tests/gamaTests/TerminalCapabilityTests.swift` (`@Suite("Terminal capabilities and cell diff")`)

- [ ] **Step 1: Run the catalog check and confirm it fails**

From the repository root:

```bash
python3 - <<'PY'
from pathlib import Path
root = Path("/Users/donaldfilimon/Desktop/Gama")
files = sorted(
    p.name for p in (root / "Tests/gamaTests").glob("*.swift")
    if p.name != "TestSupport.swift"
)
text = (root / "docs/Testing.md").read_text()
missing = [name for name in files if f"`{name}`" not in text]
print("\n".join(missing) if missing else "none")
raise SystemExit(1 if missing else 0)
PY
```

Expected before the edit: the process prints

```text
ActionIdentityTests.swift
TerminalCapabilityTests.swift
```

and exits 1. `TestSupport.swift` is the helper file the table already describes as having no suite, so the check skips it.

- [ ] **Step 2: Insert the two rows**

In `docs/Testing.md`, after the `ActionTests.swift` row, add:

```markdown
| `ActionIdentityTests.swift` | Action identity — filter `ActionIdentityTests` |
```

After the `StyleTests.swift` row and before `TerminalRescueTests.swift`, add:

```markdown
| `TerminalCapabilityTests.swift` | Terminal capabilities and cell diff — filter `TerminalCapabilityTests` |
```

The filter column names the source identifier, matching the heading of that table.

- [ ] **Step 3: Run the catalog check and confirm it passes**

From the repository root:

```bash
python3 - <<'PY'
from pathlib import Path
root = Path("/Users/donaldfilimon/Desktop/Gama")
files = sorted(
    p.name for p in (root / "Tests/gamaTests").glob("*.swift")
    if p.name != "TestSupport.swift"
)
text = (root / "docs/Testing.md").read_text()
missing = [name for name in files if f"`{name}`" not in text]
print("\n".join(missing) if missing else "none")
raise SystemExit(1 if missing else 0)
PY
```

Expected: the process prints `none` and exits 0.

- [ ] **Step 4: Commit**

```bash
git add docs/Testing.md
git commit -m "$(cat <<'EOF'
docs(test): list the action-identity and terminal-capability suites

The suite table omitted two files that already live in Tests/gamaTests.
EOF
)"
```

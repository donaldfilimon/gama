# Import Gama Studio into the framework repository

Date: 2026-09-23. Requested by Donald: move all of gama into the Gama checkout.
He chose the "Studio into Gama" option. Gama Studio (until now its own
local-only repository, 46+ commits, no remote) becomes the `GamaStudio/`
subdirectory of `donaldfilimon/gama`, with its history kept, and lands through
a pull request because `main` is protected.

Spec: none beyond this plan and Donald's choice. Rulings below are the
controller's.

## Global Constraints

- **History is kept.** Import with `git subtree add --prefix=GamaStudio`
  from the local gama-studio repository's `main`. Do not squash.
- **Studio's behavior does not change.** No source edits beyond path and
  identity fixes. Its `Package.swift` keeps depending on
  `https://github.com/donaldfilimon/gama` at revision
  `2ef325c120674cfe218de44f492f435ff50a28e7`. `NativeRegion` exists only in
  open PR #107, so a local-path dependency on this checkout's framework
  would not compile against `main` yet. Switching to `.package(path: "..")`
  is a follow-up once #107 merges.
- **The framework does not change.** No edits under `Sources/`, `Tests/`,
  `Package.swift`, `scripts/`, or `.github/`. GamaStudio is not added to
  `scripts/check.sh`'s `gates` array or to CI; it keeps its own gate.
- **Studio's gate must pass from its new location:**
  `cd GamaStudio && ./tools/check.sh >| <log> 2>&1; echo EXIT:$?`. Green only
  when the log ends `check.sh: PASSED`. Run it in this worktree
  (`/private/tmp/gama-import-studio`, outside iCloud), never in
  `~/Desktop/Gama`.
- **The framework's documentation checkers must stay green:** run
  `python3 scripts/<c>.py --self-test .` for `check-doc-links`,
  `evidence-locality`, and `referenced-paths`, plus
  `./scripts/check-boundaries.sh --source-policies-only`. Root `AGENTS.md`,
  `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, `docs/**`, and `tasks/*.md`
  are scanned. Never backtick a root-anchored path that does not exist, and
  never put a commit-anchored evidence claim outside `docs/Capabilities.md`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commit on branch `feat/import-gama-studio`. Never push; the controller pushes.

## Task 1: Import the history

- Run `git subtree add --prefix=GamaStudio <path to local gama-studio> main`
  in the worktree. The controller supplies the path and confirms that
  repository's tree is clean first.
- Verify: `git log --oneline -- GamaStudio | wc -l` is at least the source
  repository's commit count. `GamaStudio/Package.swift` exists. No `.build`
  or other ignored output was imported (`git ls-files GamaStudio | grep
  -c '\.build/'` is 0).

## Task 2: Make Studio correct at its new location

- Find every reference to the old location or identity inside `GamaStudio/`
  (`~/dev/active/gama-studio`, `dev/active/gama-studio`, "no remote",
  "local-only", "Commit on `main`") and update it. The package now lives at
  `GamaStudio/` in `donaldfilimon/gama`. Changes land through pull requests
  to that repository. Its gate still runs from `GamaStudio/`.
- Check `GamaStudio/tools/check.sh` and the Xcode project
  (`GamaStudio/Apps/GamaStudioApp/GamaStudioApp.xcodeproj`) for paths that
  assume the package root is the repository root (for example
  `git rev-parse --show-toplevel`). Fix only what breaks.
- Keep ADR history intact. Studio's `docs/adr` numbering is its own and
  does not merge with the framework's.
- Run Studio's gate from `GamaStudio/` until `check.sh: PASSED`. Record the
  test count.

## Task 3: Introduce GamaStudio to the framework docs

- Root `AGENTS.md` and `CLAUDE.md`:
  - `GamaStudio/` is a separate SwiftPM package, the Gama Studio 3D
    authoring app, with its own `AGENTS.md` and gate.
  - It is not a framework product, it is not in `scripts/check.sh` or CI,
    and it depends on the framework by pinned revision until #107 merges.
  - Keep each file's existing style.
- Root `README.md`: one sentence pointing to `GamaStudio/`.
- `docs/README.md`: nothing unless an index row fits naturally.
- Run the framework documentation checkers listed in Global Constraints,
  all exit 0.

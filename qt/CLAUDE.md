# CLAUDE.md

See AGENTS.md — canonical. This is the `qt/` package inside `donaldfilimon/gama`; it is not the Gama framework at `..`.

<!-- machine-git-policy -->
## Git workflow (machine policy, 2026-08-27)

This package has no repository of its own any more: git state is the
enclosing `donaldfilimon/gama` checkout's, and its protected `main` takes
changes through pull requests. Do not create
branches or worktrees by default; they are for tasks that genuinely need
isolation, or when Donald asks. Any worktree or topic branch created here
must be merged back into this checkout's default branch, the worktree
removed, and the branch deleted, before pushing and before the task is
called done. Full policy: `~/.claude/CLAUDE.md` (*Git discipline*).
<!-- /machine-git-policy -->

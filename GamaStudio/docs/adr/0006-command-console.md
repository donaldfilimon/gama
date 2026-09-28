# ADR 0006: The command console parses into the same commands

Status: Accepted (2026-09-23)

## Context

The spec (§34) asks for a live command console that "parse[s] commands into
the same command bus", with examples such as `add sphere`,
`move sphere 0 1 0`, `metallic 0.8`, and `duplicate selected`. `AGENTS.md`
listed it as the next phase after USD persistence (ADR 0005). Donald asked
for it on 2026-09-23.

The invariant it must respect is `AGENTS.md` invariant 2: every mutation is
a `DocumentCommand` executed through `EditorSession`, and the editor UI
reaches the session only through `StudioModel` (ADR 0003).

## Decision

1. **A new `GamaConsole` target, standard library only.**
   `ConsoleParser(document:selection:).parse(_:)` turns one line into a
   `ConsoleAction`. It reads the document and selection and edits nothing.
   `tools/check.sh` applies the same import ban as to `GamaAuthoring` and
   `GamaUSD`.
2. **Document edits parse to the existing commands, nothing new.** Each verb
   becomes a command the panels already produce:
   - `move`, `position`, and `scale` become `SetComponent(.transform)`;
   - `color`, `metallic`, and `roughness` become
     `SetComponent(.material)`, starting from `Material()` when the entity
     has none;
   - `intensity` becomes `SetComponent(.light)`, and `fov` becomes
     `SetComponent(.camera)`;
   - `hide`, `show`, `lock`, and `unlock` become
     `SetComponent(.visibility)`;
   - `rename`, `delete`, `duplicate`, and `parent` become `RenameEntity`,
     `DeleteEntity`, `DuplicateEntity`, and `ReparentEntity`.

   One target runs one command through `EditorSession.execute`, so its
   undo label is the command's own, exactly as from a panel. Several
   targets run as one transaction labelled `<Verb> N Entities`: one undo
   step.
3. **Editor intents call the model's own methods.** `add …`, `select`,
   `undo`, and `redo` parse to intents that `StudioModel.runConsole`
   dispatches to the methods the toolbar and panels call (`addPrimitive`,
   `addLight`, `addCamera`, `select`, `undo`, `redo`). Naming, placement,
   and select-what-you-created stay in one place, and `add sphere` leaves
   the same document, selection, and undo label as the Add Sphere button
   (tested).
4. **Targets.** A target is:
   - `selected`, or omitted, meaning the selection;
   - `#<id>`;
   - an entity name, matched case-insensitively and exactly;
   - `all`, for `select` only.

   A name matching several entities is refused with their ids rather than
   guessed. A target is present exactly when the first argument is not a
   number, and a quoted word is always a name, so `"2"` names an entity
   called 2.
5. **Validation stays in the session.** The parser checks grammar, target
   existence, and that a light or camera exists where the verb needs one.
   It does not re-check value ranges: `metallic 3` parses, and the session
   refuses it as it would from any surface. Parse errors and refusals are
   logged. Neither changes the document, and a refusal left over from an
   earlier action is not reported against the next line.
6. **UI.** A "Console" panel sits above the status line. It shows the last
   three exchanges and an input field. The field is gama's `TextField`
   wrapped so Enter submits: `TextField` declines Enter, and the wrapper
   handles it in the key handler rather than as a node action, because a
   pointer press invokes a node's action and a click into the field must
   not submit (tested). The input text and a 50-entry log are editor state
   on `StudioModel`, never in the document.

## Consequences

- A new surface (AI proposals, graphs, scripts) can reuse `ConsoleParser`,
  or emit the same commands directly, and inherit undo, validation, and
  bridge sync.
- `GamaConsoleTests` pins:
  - console-versus-direct-command equality of document and undo label for
    eight verbs;
  - multi-target one-step undo;
  - target resolution, including ambiguity and quoted numbers;
  - every error message;
  - session-side refusal.

  `ConsoleTests` covers the funnel end to end: bridge convergence,
  `onDocumentChange`, the log, and typing plus Enter in the real panel.
  Removing the Enter wrapper fails the panel test (measured 2026-09-23).
- Not built:
  - `rotate`, which needs a trigonometry decision for the stdlib-only
    target;
  - `find` queries;
  - `export usdz`, which waits on USDZ itself (ADR 0005);
  - command history recall (up and down arrows);
  - a keyboard shortcut to focus the console. The field is reached by
    clicking it, or with Shift-Tab from the first control.

#ifndef GAMA_TUI_SIGNAL_H
#define GAMA_TUI_SIGNAL_H

#include <signal.h>

/* Flags shared between POSIX signal handlers and ordinary code.
 *
 * Swift has no way to spell C's `volatile sig_atomic_t`: a Swift `static var`
 * typed `sig_atomic_t` gets none of the access semantics the C standard
 * requires, and `nonisolated(unsafe)` only silences actor-isolation checks.
 * Keep handler-shared storage here, where the required semantics are explicit.
 *
 * The implementation requires lock-free atomics for `sig_atomic_t`. Handler
 * stores are therefore allocation-free and lock-free, while the event loop can
 * drain the resize latch with one indivisible exchange instead of a racy
 * read-then-clear pair. */

/** Records whether terminal rescue handlers currently own the process signals. */
void gama_tui_set_armed(int value);

/** Returns whether terminal rescue handlers currently own the process signals. */
int gama_tui_get_armed(void);

/** Records that the terminal size may have changed. */
void gama_tui_set_resize_pending(int value);

/** Atomically clears and returns the pending terminal-resize flag. */
int gama_tui_take_resize_pending(void);

#endif

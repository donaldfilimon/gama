#ifndef GAMA_TUI_SIGNAL_H
#define GAMA_TUI_SIGNAL_H

#if !defined(_WIN32)

#include <termios.h>

/* Process-global POSIX terminal rescue.
 *
 * Signal handlers must not enter Swift: even a closure that appears to touch
 * only static data can invoke Swift exclusivity, initialization, or runtime
 * machinery. This target therefore owns every byte reachable from handler
 * context: terminal descriptors and state, saved signal dispositions, restore
 * bytes, and the `volatile sig_atomic_t` latches.
 *
 * `gama_tui_signal_arm`, `gama_tui_signal_disarm`, and
 * `gama_tui_signal_restore_now` are ordinary/atexit lifecycle calls. The
 * resize-latch functions are also safe to call from signal context. */

/**
 * Saves the terminal and host dispositions, then installs Gama's handlers.
 * Returns zero on success or an errno value on failure.
 */
int gama_tui_signal_arm(
    int input_fd,
    int output_fd,
    const struct termios *original_termios
);

/**
 * Restores every host disposition and releases the saved terminal state.
 * Returns zero on success or the first errno value observed while restoring.
 */
int gama_tui_signal_disarm(void);

/** Returns whether terminal rescue handlers currently own the process signals. */
int gama_tui_signal_is_armed(void);

/** Restores termios and terminal presentation at most once. */
void gama_tui_signal_restore_now(void);

/** Records that the terminal size may have changed. */
void gama_tui_signal_mark_resize_pending(void);

/** Atomically clears and returns the pending terminal-resize flag. */
int gama_tui_signal_take_resize_pending(void);

#endif

#endif

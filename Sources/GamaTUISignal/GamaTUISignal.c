#include "include/GamaTUISignal.h"

#if !defined(_WIN32)

#include <errno.h>
#include <signal.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum {
    GAMA_TUI_SIGNAL_COUNT = 5,
    GAMA_TUI_TERMINATING_SIGNAL_COUNT = 4,
};

static const int gama_tui_signals[GAMA_TUI_SIGNAL_COUNT] = {
    SIGTERM,
    SIGHUP,
    SIGINT,
    SIGQUIT,
    SIGWINCH,
};

static const char gama_tui_restore_sequence[] =
    "\x1b[?1006l\x1b[?1000l\x1b[0m\x1b[?25h\x1b[?1049l";

static struct termios gama_tui_saved_termios;
static struct sigaction gama_tui_saved_actions[GAMA_TUI_SIGNAL_COUNT];
static int gama_tui_saved_input_fd = -1;
static int gama_tui_saved_output_fd = -1;
static volatile sig_atomic_t gama_tui_has_saved_actions = 0;
static int gama_tui_atexit_registered = 0;
static volatile sig_atomic_t gama_tui_armed = 0;
static volatile sig_atomic_t gama_tui_resize_pending = 0;
static volatile sig_atomic_t gama_tui_installing_handlers = 0;
static volatile sig_atomic_t gama_tui_pending_termination = 0;

_Static_assert(
    __atomic_always_lock_free(sizeof(sig_atomic_t), 0),
    "GamaTUISignal requires lock-free sig_atomic_t operations"
);

static void gama_tui_managed_signal_set(sigset_t *set) {
    sigemptyset(set);
    for (size_t index = 0; index < GAMA_TUI_SIGNAL_COUNT; ++index) {
        sigaddset(set, gama_tui_signals[index]);
    }
}

static void gama_tui_write_restore_sequence(void) {
    if (gama_tui_saved_output_fd < 0) {
        return;
    }

    size_t offset = 0;
    const size_t count = sizeof(gama_tui_restore_sequence) - 1;
    while (offset < count) {
        ssize_t written = write(
            gama_tui_saved_output_fd,
            gama_tui_restore_sequence + offset,
            count - offset
        );
        if (written > 0) {
            offset += (size_t)written;
            continue;
        }
        if (written < 0 && errno == EINTR) {
            continue;
        }
        break;
    }
}

static void gama_tui_restore_termios(void) {
    if (gama_tui_saved_input_fd < 0) {
        return;
    }

    while (tcsetattr(
        gama_tui_saved_input_fd,
        TCSANOW,
        &gama_tui_saved_termios
    ) != 0 && errno == EINTR) {}
}

static int gama_tui_begin_restore(void) {
    return __atomic_exchange_n(
        &gama_tui_armed,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    ) != 0;
}

void gama_tui_signal_restore_now(void) {
    if (!gama_tui_begin_restore()) {
        return;
    }

    gama_tui_write_restore_sequence();
    gama_tui_restore_termios();
}

static int gama_tui_restore_saved_actions(void);

static void gama_tui_terminating_handler(int signal_number) {
    int saved_errno = errno;

    // sigprocmask only blocks the arming thread. A process-wide handler may
    // therefore run on another host thread while the remaining handlers are
    // still being installed. Defer that signal until every displaced action
    // is available and the complete set can be restored without recursion.
    if (__atomic_load_n(
        &gama_tui_installing_handlers,
        __ATOMIC_SEQ_CST
    ) != 0) {
        __atomic_store_n(
            &gama_tui_pending_termination,
            (sig_atomic_t)signal_number,
            __ATOMIC_SEQ_CST
        );
        errno = saved_errno;
        return;
    }

    // A terminal/PTY output descriptor may be blocking with a full queue.
    // Fatal-signal rescue prioritizes the write-free termios restore and leaves
    // presentation escape bytes to ordinary teardown paths.
    if (gama_tui_begin_restore()) {
        gama_tui_restore_termios();
    }

    // Re-raise through the process disposition Gama displaced. Restoring all
    // managed actions first also ensures that a host handler which returns
    // does not leave Gama intercepting later signals permanently.
    if (gama_tui_restore_saved_actions() != 0) {
        _exit(128 + signal_number);
    }
    raise(signal_number);
    // SIG_IGN and host handlers that return resume interrupted host code.
    // Do not leak errno changes from Gama's restoration syscalls into it.
    errno = saved_errno;
}

static void gama_tui_resize_handler(int signal_number) {
    (void)signal_number;
    if (__atomic_load_n(&gama_tui_armed, __ATOMIC_SEQ_CST) != 0) {
        gama_tui_signal_mark_resize_pending();
    }
}

static int gama_tui_restore_saved_actions(void) {
    if (__atomic_load_n(
        &gama_tui_has_saved_actions,
        __ATOMIC_SEQ_CST
    ) == 0) {
        return 0;
    }

    int result = 0;
    for (size_t index = 0; index < GAMA_TUI_SIGNAL_COUNT; ++index) {
        if (sigaction(
            gama_tui_signals[index],
            &gama_tui_saved_actions[index],
            NULL
        ) != 0 && result == 0) {
            result = errno;
        }
    }
    __atomic_store_n(
        &gama_tui_has_saved_actions,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
    return result;
}

static int gama_tui_publish_saved_actions(void) {
    for (size_t index = 0; index < GAMA_TUI_SIGNAL_COUNT; ++index) {
        if (sigaction(
            gama_tui_signals[index],
            NULL,
            &gama_tui_saved_actions[index]
        ) != 0) {
            return errno;
        }
    }
    __atomic_store_n(
        &gama_tui_has_saved_actions,
        (sig_atomic_t)1,
        __ATOMIC_SEQ_CST
    );
    return 0;
}

static int gama_tui_install_saved_handlers(void) {
    struct sigaction terminating_action;
    struct sigaction resize_action;
    memset(&terminating_action, 0, sizeof(terminating_action));
    memset(&resize_action, 0, sizeof(resize_action));
    terminating_action.sa_handler = gama_tui_terminating_handler;
    resize_action.sa_handler = gama_tui_resize_handler;
    gama_tui_managed_signal_set(&terminating_action.sa_mask);
    gama_tui_managed_signal_set(&resize_action.sa_mask);
    terminating_action.sa_flags = 0;
    // Do not request SA_RESTART. poll(2) is allowed to return EINTR, and the
    // Swift event loop drains the resize latch on that path immediately.
    resize_action.sa_flags = 0;

    __atomic_store_n(
        &gama_tui_installing_handlers,
        (sig_atomic_t)1,
        __ATOMIC_SEQ_CST
    );
    int result = 0;
    for (size_t index = 0; index < GAMA_TUI_SIGNAL_COUNT; ++index) {
        const struct sigaction *action = index < GAMA_TUI_TERMINATING_SIGNAL_COUNT
            ? &terminating_action
            : &resize_action;
        if (sigaction(gama_tui_signals[index], action, NULL) != 0) {
            result = errno;
            break;
        }
    }
    if (result == 0) {
        __atomic_store_n(&gama_tui_armed, (sig_atomic_t)1, __ATOMIC_SEQ_CST);
    }
    __atomic_store_n(
        &gama_tui_installing_handlers,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
    return result;
}

int gama_tui_signal_arm(
    int input_fd,
    int output_fd,
    const struct termios *original_termios
) {
    if (original_termios == NULL || input_fd < 0 || output_fd < 0) {
        return EINVAL;
    }
    if (__atomic_load_n(&gama_tui_armed, __ATOMIC_SEQ_CST) != 0
        || __atomic_load_n(
            &gama_tui_has_saved_actions,
            __ATOMIC_SEQ_CST
        ) != 0) {
        return EBUSY;
    }

    sigset_t managed;
    sigset_t previous_mask;
    gama_tui_managed_signal_set(&managed);
    if (sigprocmask(SIG_BLOCK, &managed, &previous_mask) != 0) {
        return errno;
    }

    int result = 0;
    if (!gama_tui_atexit_registered) {
        if (atexit(gama_tui_signal_restore_now) != 0) {
            result = ENOMEM;
        } else {
            gama_tui_atexit_registered = 1;
        }
    }

    gama_tui_saved_termios = *original_termios;
    gama_tui_saved_input_fd = input_fd;
    gama_tui_saved_output_fd = output_fd;
    __atomic_store_n(
        &gama_tui_resize_pending,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
    __atomic_store_n(
        &gama_tui_pending_termination,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );

    if (result == 0) {
        result = gama_tui_publish_saved_actions();
    }
    if (result == 0) {
        result = gama_tui_install_saved_handlers();
    }

    if (result != 0) {
        __atomic_store_n(&gama_tui_armed, (sig_atomic_t)0, __ATOMIC_SEQ_CST);
        (void)gama_tui_restore_saved_actions();
        gama_tui_saved_input_fd = -1;
        gama_tui_saved_output_fd = -1;
    }

    if (sigprocmask(SIG_SETMASK, &previous_mask, NULL) != 0 && result == 0) {
        result = errno;
        __atomic_store_n(&gama_tui_armed, (sig_atomic_t)0, __ATOMIC_SEQ_CST);
        (void)gama_tui_restore_saved_actions();
        gama_tui_saved_input_fd = -1;
        gama_tui_saved_output_fd = -1;
    }
    int pending_signal = (int)__atomic_exchange_n(
        &gama_tui_pending_termination,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
    if (pending_signal != 0) {
        if (result == 0) {
            result = EINTR;
        }
        raise(pending_signal);
    } else if (result == 0
        && __atomic_load_n(&gama_tui_armed, __ATOMIC_SEQ_CST) == 0) {
        // A host disposition that returned may have completed restoration
        // between installation and this function's return.
        result = EINTR;
    }
    return result;
}

int gama_tui_signal_disarm(void) {
    sigset_t managed;
    sigset_t previous_mask;
    gama_tui_managed_signal_set(&managed);
    int blocked = sigprocmask(SIG_BLOCK, &managed, &previous_mask) == 0;
    int result = blocked ? 0 : errno;

    __atomic_store_n(&gama_tui_armed, (sig_atomic_t)0, __ATOMIC_SEQ_CST);
    __atomic_store_n(
        &gama_tui_installing_handlers,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
    __atomic_store_n(
        &gama_tui_resize_pending,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
    int restore_result = gama_tui_restore_saved_actions();
    if (result == 0) {
        result = restore_result;
    }
    gama_tui_saved_input_fd = -1;
    gama_tui_saved_output_fd = -1;

    if (blocked && sigprocmask(SIG_SETMASK, &previous_mask, NULL) != 0
        && result == 0) {
        result = errno;
    }
    return result;
}

int gama_tui_signal_is_armed(void) {
    return (int)__atomic_load_n(&gama_tui_armed, __ATOMIC_SEQ_CST);
}

void gama_tui_signal_mark_resize_pending(void) {
    __atomic_store_n(
        &gama_tui_resize_pending,
        (sig_atomic_t)1,
        __ATOMIC_SEQ_CST
    );
}

int gama_tui_signal_take_resize_pending(void) {
    return (int)__atomic_exchange_n(
        &gama_tui_resize_pending,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
}

#endif

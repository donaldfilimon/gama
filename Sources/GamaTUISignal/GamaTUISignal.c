#include "include/GamaTUISignal.h"

static volatile sig_atomic_t gama_tui_armed = 0;
static volatile sig_atomic_t gama_tui_resize_pending = 0;

_Static_assert(
    __atomic_always_lock_free(sizeof(sig_atomic_t), 0),
    "GamaTUISignal requires lock-free sig_atomic_t operations"
);

void gama_tui_set_armed(int value) {
    __atomic_store_n(&gama_tui_armed, (sig_atomic_t)value, __ATOMIC_SEQ_CST);
}

int gama_tui_get_armed(void) {
    return (int)__atomic_load_n(&gama_tui_armed, __ATOMIC_SEQ_CST);
}

void gama_tui_set_resize_pending(int value) {
    __atomic_store_n(
        &gama_tui_resize_pending,
        (sig_atomic_t)value,
        __ATOMIC_SEQ_CST
    );
}

int gama_tui_take_resize_pending(void) {
    return (int)__atomic_exchange_n(
        &gama_tui_resize_pending,
        (sig_atomic_t)0,
        __ATOMIC_SEQ_CST
    );
}

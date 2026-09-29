#ifndef GAMA_EMBED_H
#define GAMA_EMBED_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque context handle. The struct is never defined; the pointer type
 * exists so C hosts get compile-time type safety instead of `void *`.
 * Every function is single-render-thread only, and a context must not be
 * reused after destruction.
 */
typedef struct GamaEmbedContextRecord *GamaEmbedContext;

/** Status codes returned by the int32_t-returning entry points. */
enum {
    /** Success. */
    GAMA_EMBED_OK = 0,
    /** The context pointer was NULL. */
    GAMA_EMBED_ERR_NULL_CONTEXT = -1,
    /** The key code did not translate to an input event. */
    GAMA_EMBED_ERR_INVALID_KEY = -2,
    /**
     * The encoded frame exceeded INT32_MAX bytes (written to
     * *output_length by gama_embed_v1_frame, which then returns NULL).
     */
    GAMA_EMBED_ERR_FRAME_TOO_LARGE = -3,
    /**
     * A pointer phase, kind, button or modifier code was outside the
     * GAMA_EMBED_POINTER_* tables below.
     */
    GAMA_EMBED_ERR_INVALID_POINTER = -4
};

/**
 * Pointer sample codes for gama_embed_v1_pointer_event (ADR 0018). The host
 * only translates what the device did; Gama recognizes taps, drags, long
 * presses, hover and scroll from the samples.
 */
enum {
    /* Phases. */
    /** A button or contact went down. */
    GAMA_EMBED_POINTER_DOWN = 0,
    /** The pointer moved (a drag while a button is held). */
    GAMA_EMBED_POINTER_MOVE = 1,
    /** The button or contact was released. */
    GAMA_EMBED_POINTER_UP = 2,
    /** The platform cancelled the contact; a captured gesture is cancelled. */
    GAMA_EMBED_POINTER_CANCEL = 3,
    /** The pointer moved with nothing pressed. */
    GAMA_EMBED_POINTER_HOVER = 4,
    /** A wheel or trackpad scroll; the scroll arguments carry the delta. */
    GAMA_EMBED_POINTER_SCROLL = 5,
    /** A sample with no movement, delivered at the pointer deadline. */
    GAMA_EMBED_POINTER_STATIONARY = 6,

    /* Device kinds. */
    /** A mouse or trackpad cursor. */
    GAMA_EMBED_POINTER_MOUSE = 0,
    /** A finger on a touch surface. */
    GAMA_EMBED_POINTER_TOUCH = 1,
    /** A stylus. */
    GAMA_EMBED_POINTER_PEN = 2,

    /* Buttons (0...31 are accepted). */
    /** The primary (left) button or a touch contact. */
    GAMA_EMBED_POINTER_BUTTON_PRIMARY = 0,
    /** The secondary (right) button. */
    GAMA_EMBED_POINTER_BUTTON_SECONDARY = 1,
    /** The middle button. */
    GAMA_EMBED_POINTER_BUTTON_MIDDLE = 2,

    /* Modifier bits, combined with |. */
    /** Shift. */
    GAMA_EMBED_POINTER_SHIFT = 1,
    /** Control. */
    GAMA_EMBED_POINTER_CONTROL = 2,
    /** Option (Alt). */
    GAMA_EMBED_POINTER_OPTION = 4,
    /** Command (Windows key, Meta). */
    GAMA_EMBED_POINTER_COMMAND = 8,

    /**
     * A timestamp meaning "this host has no clock" (any negative value
     * does), and the deadline value meaning "no press is waiting on one".
     */
    GAMA_EMBED_POINTER_NO_TIME = -1
};

/**
 * The ABI revision of this header and the linked library: always 1 for the
 * gama_embed_v1_* family. Interrogate at runtime before trusting newer
 * entry points.
 */
int32_t gama_embed_v1_abi_version(void);

/**
 * Creates the built-in diagnostic application used to validate a pure-C
 * host; application-specific Swift bootstraps use GamaEmbed.makeContext(app:)
 * instead. Dimensions are clamped to 1...INT32_MAX (the cell grid
 * additionally enforces its own maximum cell count). Release the returned
 * context with gama_embed_v1_context_destroy.
 */
GamaEmbedContext gama_embed_v1_context_create(int32_t columns, int32_t rows);

/** Releases a context. The pointer must not be reused afterwards. */
void gama_embed_v1_context_destroy(GamaEmbedContext context);

/**
 * Resizes the grid; dimensions are clamped to 1...INT32_MAX on both axes.
 * Returns GAMA_EMBED_OK or GAMA_EMBED_ERR_NULL_CONTEXT.
 */
int32_t gama_embed_v1_resize(GamaEmbedContext context, int32_t columns, int32_t rows);

/**
 * Translates and delivers one key event. Returns GAMA_EMBED_OK,
 * GAMA_EMBED_ERR_NULL_CONTEXT, or GAMA_EMBED_ERR_INVALID_KEY for a code
 * that does not translate.
 */
int32_t gama_embed_v1_key(
    GamaEmbedContext context,
    int32_t code,
    int32_t unicode_scalar,
    int32_t shift,
    int32_t control
);

/**
 * Delivers one pointer press/release at a grid position. Returns
 * GAMA_EMBED_OK or GAMA_EMBED_ERR_NULL_CONTEXT.
 */
int32_t gama_embed_v1_pointer(
    GamaEmbedContext context,
    int32_t column,
    int32_t row,
    int32_t pressed
);

/**
 * Delivers one rich pointer sample at a grid position (ADR 0018). phase,
 * kind, button and modifiers take the GAMA_EMBED_POINTER_* codes;
 * scroll_columns and scroll_rows carry a GAMA_EMBED_POINTER_SCROLL delta in
 * cells (positive rows reveal the lines below, positive columns the columns
 * to the right) and are otherwise zero. pointer_id identifies the contact:
 * one pointer is captured at a time. timestamp_millis is monotonic
 * milliseconds, or GAMA_EMBED_POINTER_NO_TIME. Returns GAMA_EMBED_OK,
 * GAMA_EMBED_ERR_NULL_CONTEXT (checked first), or
 * GAMA_EMBED_ERR_INVALID_POINTER. gama_embed_v1_pointer remains the
 * primary press/release shorthand.
 */
int32_t gama_embed_v1_pointer_event(
    GamaEmbedContext context,
    int32_t phase,
    int32_t kind,
    int32_t button,
    int32_t modifiers,
    int32_t column,
    int32_t row,
    int32_t scroll_columns,
    int32_t scroll_rows,
    int32_t pointer_id,
    int64_t timestamp_millis
);

/**
 * Writes the pending long-press deadline to *output_millis (the same clock
 * the host stamps samples with), or GAMA_EMBED_POINTER_NO_TIME when no
 * press is waiting on one. A host with a timer delivers a
 * GAMA_EMBED_POINTER_STATIONARY sample for the captured pointer at that
 * time; re-query after every pointer call. output_millis may be NULL.
 * Returns GAMA_EMBED_OK or GAMA_EMBED_ERR_NULL_CONTEXT.
 */
int32_t gama_embed_v1_pointer_deadline(GamaEmbedContext context, int64_t *output_millis);

/**
 * Returns 1 when state changed since the last frame, 0 when clean, or
 * GAMA_EMBED_ERR_NULL_CONTEXT.
 */
int32_t gama_embed_v1_needs_frame(GamaEmbedContext context);

/**
 * Encodes the next frame into context-owned storage and returns its bytes,
 * valid until the next frame call or context destruction. A clean (not
 * dirty) frame returns NULL and writes length zero; a frame whose encoding
 * exceeds INT32_MAX bytes returns NULL and writes
 * GAMA_EMBED_ERR_FRAME_TOO_LARGE.
 */
const uint8_t *gama_embed_v1_frame(GamaEmbedContext context, int32_t *output_length);

#ifdef __cplusplus
}
#endif

#endif

#ifndef GAMA_EMBED_H
#define GAMA_EMBED_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque context handle. The struct is never defined; the pointer type
 * exists so C hosts get compile-time type safety instead of `void *`. */
typedef struct GamaEmbedContextRecord *GamaEmbedContext;

/* Status codes returned by the int32_t-returning entry points. */
enum {
    GAMA_EMBED_OK = 0,
    /* The context pointer was NULL. */
    GAMA_EMBED_ERR_NULL_CONTEXT = -1,
    /* The key code did not translate to an input event. */
    GAMA_EMBED_ERR_INVALID_KEY = -2,
    /* The encoded frame exceeded INT32_MAX bytes (written to *output_length
     * by gama_embed_v1_frame, which then returns NULL). */
    GAMA_EMBED_ERR_FRAME_TOO_LARGE = -3
};

/* The ABI revision of this header and the linked library: always 1 for the
 * gama_embed_v1_* family. Interrogate at runtime before trusting newer
 * entry points. */
int32_t gama_embed_v1_abi_version(void);

/* Creates the built-in diagnostic application used to validate a pure-C host.
 * Application-specific Swift bootstraps may instead use
 * GamaEmbed.makeContext(app:). Every function is single-render-thread only.
 * The frame pointer is valid until the next frame call or context
 * destruction. Context values must not be reused after destruction.
 * Dimensions are clamped to 1...INT32_MAX on create and resize (the cell
 * grid itself additionally enforces its own maximum cell count).
 * A clean (not dirty) frame returns NULL and writes length zero; a frame
 * whose encoding exceeds INT32_MAX bytes returns NULL and writes
 * GAMA_EMBED_ERR_FRAME_TOO_LARGE. */
GamaEmbedContext gama_embed_v1_context_create(int32_t columns, int32_t rows);
void gama_embed_v1_context_destroy(GamaEmbedContext context);
int32_t gama_embed_v1_resize(GamaEmbedContext context, int32_t columns, int32_t rows);
int32_t gama_embed_v1_key(
    GamaEmbedContext context,
    int32_t code,
    int32_t unicode_scalar,
    int32_t shift,
    int32_t control
);
int32_t gama_embed_v1_pointer(
    GamaEmbedContext context,
    int32_t column,
    int32_t row,
    int32_t pressed
);
int32_t gama_embed_v1_needs_frame(GamaEmbedContext context);
const uint8_t *gama_embed_v1_frame(GamaEmbedContext context, int32_t *output_length);

#ifdef __cplusplus
}
#endif

#endif

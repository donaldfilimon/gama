#ifndef GAMA_EMBED_H
#define GAMA_EMBED_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *GamaEmbedContext;

/* Creates the built-in diagnostic application used to validate a pure-C host.
 * Application-specific Swift bootstraps may instead use
 * GamaEmbed.makeContext(app:). Every function is single-render-thread only.
 * The frame pointer is valid
 * until the next frame call or context destruction. Context values must not
 * be reused after destruction. 0 means success, -1 means a null context, and
 * -2 means an invalid key code. Resize dimensions below one are clamped to
 * one. A clean (not dirty) frame returns NULL and writes length zero. */
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

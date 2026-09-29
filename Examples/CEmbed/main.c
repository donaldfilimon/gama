#include <stdint.h>
#include <stdio.h>
#include "GamaEmbed.h"

static int consume_one_frame(GamaEmbedContext context) {
    int32_t length = 0;
    const uint8_t *bytes = gama_embed_v1_frame(context, &length);
    if (bytes == NULL || length < 20) return -1;
    return bytes[0] == 'G' && bytes[1] == 'A' && bytes[2] == 'M' && bytes[3] == 'A'
        ? 0 : -2;
}

int main(void) {
    if (gama_embed_v1_abi_version() != 1) return 9;
    GamaEmbedContext context = gama_embed_v1_context_create(40, 12);
    if (context == NULL) return 10;
    if (gama_embed_v1_resize(context, INT32_MAX, INT32_MAX) != GAMA_EMBED_OK) return 17;
    if (gama_embed_v1_resize(context, 40, 12) != GAMA_EMBED_OK) return 18;
    if (gama_embed_v1_key(context, 999, 0, 0, 0) != GAMA_EMBED_ERR_INVALID_KEY) return 19;
    if (gama_embed_v1_needs_frame(NULL) != GAMA_EMBED_ERR_NULL_CONTEXT) return 20;
    if (gama_embed_v1_needs_frame(context) != 1) return 11;
    if (consume_one_frame(context) != 0) return 12;
    if (gama_embed_v1_key(context, 7, 0, 0, 0) != 0) return 13;
    if (gama_embed_v1_key(context, 5, 0, 0, 0) != 0) return 14;
    if (gama_embed_v1_needs_frame(context) != 1) return 15;
    if (consume_one_frame(context) != 0) return 16;

    /* Rich pointer samples (ADR 0018): the diagnostic app registers no
     * pointer handler, so a press never waits on a long-press deadline. */
    int64_t deadline = 0;
    if (gama_embed_v1_pointer_deadline(NULL, &deadline) != GAMA_EMBED_ERR_NULL_CONTEXT) return 21;
    if (gama_embed_v1_pointer_event(context, 99, GAMA_EMBED_POINTER_MOUSE,
            GAMA_EMBED_POINTER_BUTTON_PRIMARY, 0, 0, 0, 0, 0, 0,
            GAMA_EMBED_POINTER_NO_TIME) != GAMA_EMBED_ERR_INVALID_POINTER) return 22;
    if (gama_embed_v1_pointer_event(context, GAMA_EMBED_POINTER_HOVER, GAMA_EMBED_POINTER_MOUSE,
            GAMA_EMBED_POINTER_BUTTON_PRIMARY, GAMA_EMBED_POINTER_SHIFT, 2, 1, 0, 0, 0,
            1000) != GAMA_EMBED_OK) return 23;
    if (gama_embed_v1_pointer_event(context, GAMA_EMBED_POINTER_SCROLL, GAMA_EMBED_POINTER_MOUSE,
            GAMA_EMBED_POINTER_BUTTON_PRIMARY, 0, 2, 1, 0, 1, 0, 1010) != GAMA_EMBED_OK) return 24;
    if (gama_embed_v1_pointer_event(context, GAMA_EMBED_POINTER_DOWN, GAMA_EMBED_POINTER_TOUCH,
            GAMA_EMBED_POINTER_BUTTON_PRIMARY, 0, 2, 1, 0, 0, 7, 1020) != GAMA_EMBED_OK) return 25;
    if (gama_embed_v1_pointer_deadline(context, &deadline) != GAMA_EMBED_OK) return 26;
    if (deadline != GAMA_EMBED_POINTER_NO_TIME) return 27;
    if (gama_embed_v1_pointer_event(context, GAMA_EMBED_POINTER_UP, GAMA_EMBED_POINTER_TOUCH,
            GAMA_EMBED_POINTER_BUTTON_PRIMARY, 0, 2, 1, 0, 0, 7, 1030) != GAMA_EMBED_OK) return 28;
    if (gama_embed_v1_pointer_deadline(context, NULL) != GAMA_EMBED_OK) return 29;

    gama_embed_v1_context_destroy(context);
    puts("OK — pure-C context create/input/pointer/frame/destroy round trip");
    return 0;
}

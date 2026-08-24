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
    GamaEmbedContext context = gama_embed_v1_context_create(40, 12);
    if (context == NULL) return 10;
    if (gama_embed_v1_needs_frame(context) != 1) return 11;
    if (consume_one_frame(context) != 0) return 12;
    if (gama_embed_v1_key(context, 7, 0, 0, 0) != 0) return 13;
    if (gama_embed_v1_key(context, 5, 0, 0, 0) != 0) return 14;
    if (gama_embed_v1_needs_frame(context) != 1) return 15;
    if (consume_one_frame(context) != 0) return 16;
    gama_embed_v1_context_destroy(context);
    puts("OK — pure-C context create/input/frame/destroy round trip");
    return 0;
}

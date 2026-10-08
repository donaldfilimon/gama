/* Migration oracle, test-only C consumer. Writes borrowed bytes before reuse. */
#include "GamaEmbed.h"
#include <stdio.h>
#include <stdint.h>

static int save_frame(GamaEmbedContext context, const char *path) {
    int32_t length = 0;
    const uint8_t *bytes = gama_embed_v1_frame(context, &length);
    if (!bytes || length < 20) return 1;
    if (bytes[0] != 'G' || bytes[1] != 'A' || bytes[2] != 'M' || bytes[3] != 'A') return 2;
    FILE *file = fopen(path, "wb");
    if (!file) return 3;
    int result = fwrite(bytes, 1, (size_t)length, file) == (size_t)length ? 0 : 4;
    if (fclose(file) != 0) result = 5;
    return result;
}
int main(int argc, char **argv) {
    if (argc != 3 || gama_embed_v1_abi_version() != 1) return 10;
    GamaEmbedContext context = gama_embed_v1_context_create(24, 6);
    if (!context) return 11;
    int result = save_frame(context, argv[1]);
    if (!result && gama_embed_v1_key(context, 5, 0, 0, 0) != 0) result = 12;
    if (!result) result = save_frame(context, argv[2]);
    int32_t clean_length = -99;
    if (!result && (gama_embed_v1_frame(context, &clean_length) != NULL || clean_length != 0)) result = 13;
    gama_embed_v1_context_destroy(context);
    if (!result) puts("PASS: C create/frame/Enter/frame/clean/destroy; 2 binary goldens");
    return result;
}

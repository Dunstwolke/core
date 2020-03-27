#include <picohash.h>

void compute_hash(void const *data, size_t length, void * out)
{
    picohash_ctx_t ctx;
    picohash_init_md5(&ctx);
    picohash_update(&ctx, data, length);
    picohash_final(&ctx, out);
}

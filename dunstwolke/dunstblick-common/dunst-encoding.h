#ifndef DUNSTENCODING_H
#define DUNSTENCODING_H

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    static inline int32_t map_unsigned_to_signed(uint32_t u)
    {
        int32_t n = (int32_t)u;
        return (n << 1) ^ (n >> 31);
    }

    static inline uint32_t map_signed_to_unsigned(int32_t n)
    {
        int32_t v = (n << 1) ^ (n >> 31);
        return (uint32_t)v;
    }

#ifdef __cplusplus
}
#endif

#endif // DUNSTENCODING_H

#ifndef FONTCACHE_HPP
#define FONTCACHE_HPP

#include <SDL.h>
#include <SDL_ttf.h>
#include <chrono>
#include <map>
#include <string>
#include <xstd/resource>

#include "types.hpp"

#include <sdl2++/renderer>

struct FontCache
{
    typedef std::chrono::steady_clock::time_point time_point;

    struct CachedString
    {
        xstd::resource<SDL_Texture *, SDL_DestroyTexture> texture;
        UISize size;
        time_point last_update = std::chrono::steady_clock::now();
    };

    std::map<std::string, CachedString> cache;
    xstd::resource<TTF_Font *, TTF_CloseFont> font;
    SDL_Color color = {0xFF, 0xFF, 0xFF, 0xFF};
    sdl2::renderer * renderer;

    explicit FontCache(TTF_Font * font, sdl2::renderer * renderer);

    xstd::optional<CachedString const &> render(std::string const & text);

    void cleanup(size_t maxTextures = 0);
};

#endif // FONTCACHE_HPP

#include "fontcache.hpp"

FontCache::FontCache(TTF_Font * _font, sdl2::renderer * _renderer) : cache(), font(_font), renderer(_renderer)
{
    assert(font);
    assert(renderer);
}

xstd::optional<FontCache::CachedString const &> FontCache::render(const std::string & text)
{
    if (text.empty())
        return xstd::nullopt;

    auto it = cache.find(text);
    if (it != cache.end()) {
        it->second.last_update = std::chrono::steady_clock::now();
        return it->second;
    }

    xstd::resource<SDL_Surface *, SDL_FreeSurface> surf(TTF_RenderUTF8_Blended(font.get(), text.c_str(), color));
    if (not surf)
        return xstd::nullopt;
    CachedString str{
        xstd::resource<SDL_Texture *, SDL_DestroyTexture>(SDL_CreateTextureFromSurface(*renderer, surf.get())),
        UISize{0, 0},
    };

    Uint32 format;
    int access;
    SDL_QueryTexture(str.texture.get(), &format, &access, &str.size.w, &str.size.h);

    auto [new_it, emplaced] = cache.emplace(text, std::move(str));
    assert(emplaced);
    return new_it->second;
}

void FontCache::cleanup(size_t maxTextures)
{
    if (maxTextures <= 0)
        maxTextures = cache.size();

    auto const now = std::chrono::steady_clock::now();

    for (auto it = cache.begin(); it != cache.end() and maxTextures > 0;) {
        auto age = now - it->second.last_update;
        if (age >= std::chrono::milliseconds(2500)) {
            it = cache.erase(it);
            maxTextures -= 1;
        } else {
            it++;
        }
    }
}

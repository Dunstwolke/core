#include "fontcache.hpp"


FontCache::FontCache(TTF_Font * font, sdl2::renderer * renderer) :
    cache(),
    font(font),
    renderer(renderer)
{
    assert(font);
    assert(renderer);
}

SDL_Texture * FontCache::render(const std::string & text)
{
    if(text.empty())
        return nullptr;

    auto it = cache.find(text);
    if(it != cache.end()) {
        it->second.last_update = std::chrono::steady_clock::now();
        return it->second.texture.get();
    }

    xstd::resource<SDL_Surface*,SDL_FreeSurface> surf(TTF_RenderUTF8_Blended(
        font.get(),
        text.c_str(),
        color
    ));
    if(not surf)
        return nullptr;
    CachedString str {
        xstd::resource<SDL_Texture*, SDL_DestroyTexture>(SDL_CreateTextureFromSurface(*renderer, surf.get())),
    };
    auto [ new_it, emplaced ] = cache.emplace(text, std::move(str));
    assert(emplaced);
    return new_it->second.texture.get();
}

void FontCache::cleanup(size_t maxTextures)
{
    if(maxTextures <= 0)
        maxTextures = cache.size();

    auto const now = std::chrono::steady_clock::now();

    for(auto it = cache.begin(); it != cache.end() and maxTextures > 0;)
    {
        auto age = now - it->second.last_update;
        if(age >= std::chrono::milliseconds(2500))
        {
            it = cache.erase(it);
            maxTextures -= 1;
        }
        else {
            it++;
        }
    }
}

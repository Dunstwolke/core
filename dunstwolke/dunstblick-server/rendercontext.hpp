#ifndef RENDERCONTEXT_HPP
#define RENDERCONTEXT_HPP

#include "fontcache.hpp"
#include <sdl2++/renderer>

struct RenderContext
{
    sdl2::renderer renderer;
    FontCache sansFont;
    FontCache serifFont;
    FontCache monospaceFont;

    explicit RenderContext(sdl2::renderer && ren, char const * sansTTF, char const * serifTTF, char const * monoTTF);

    FontCache & getFont(UIFont font);
};

RenderContext & context();

#endif // RENDERCONTEXT_HPP

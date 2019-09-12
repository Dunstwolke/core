#include "rendercontext.hpp"


RenderContext::RenderContext(sdl2::renderer &&ren, char const * sansTTF, char const * serifTTF, char const * monoTTF) :
    renderer(std::move(ren)),
    sansFont(TTF_OpenFont(sansTTF, 24), &renderer),
    serifFont(TTF_OpenFont(serifTTF, 24), &renderer),
    monospaceFont(TTF_OpenFont(monoTTF, 24), &renderer)
{

}

FontCache & RenderContext::getFont(UIFont font)
{
    switch(font) {
    case UIFont::sans:      return sansFont;
    case UIFont::serif:     return serifFont;
    case UIFont::monospace: return monospaceFont;
    }
}

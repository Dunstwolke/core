#include "rendercontext.hpp"

RenderContext::RenderContext(sdl2::renderer && ren, char const * sansTTF, char const * serifTTF, char const * monoTTF) :
    renderer(std::move(ren)),
    sansFont(TTF_OpenFont(sansTTF, 24), &renderer),
    serifFont(TTF_OpenFont(serifTTF, 24), &renderer),
    monospaceFont(TTF_OpenFont(monoTTF, 24), &renderer)
{}

FontCache & RenderContext::getFont(UIFont font)
{
    switch (font) {
        case UIFont::sans:
            return sansFont;
        case UIFont::serif:
            return serifFont;
        case UIFont::monospace:
            return monospaceFont;
    }
}

void RenderContext::drawBevel(const SDL_Rect & _rect, Bevel bevel)
{
    SDL_Rect rect = _rect;
    rect.w -= 1;
    rect.h -= 1;
    SDL_Color topleft;
    SDL_Color botright;
    switch (bevel) {
        case Bevel::flat:
            topleft = {0x80, 0x80, 0x80, 0xFF};
            botright = {0x80, 0x80, 0x80, 0xFF};
            break;
        case Bevel::sunken:
            topleft = {0x60, 0x60, 0x60, 0xFF};
            botright = {0xA0, 0xA0, 0xA0, 0xFF};
            break;
        case Bevel::raised:
            topleft = {0xA0, 0xA0, 0xA0, 0xFF};
            botright = {0x60, 0x60, 0x60, 0xFF};
            break;
    }
    // renderer.setColor(0x80, 0x80, 0x80);
    // renderer.fillRect(rect);

    renderer.setColor(topleft);
    renderer.drawLine(rect.x, rect.y, rect.x + rect.w, rect.y);
    // renderer.drawLine(rect.x, rect.y, rect.x, rect.y + rect.h);

    renderer.setColor(botright);
    renderer.drawLine(rect.x + rect.w, rect.y, rect.x + rect.w, rect.y + rect.h);
    // renderer.drawLine(rect.x + rect.w, rect.y + rect.h, rect.x, rect.y + rect.h);
}

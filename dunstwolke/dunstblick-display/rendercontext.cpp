#include "rendercontext.hpp"

RenderContext::RenderContext(sdl2::renderer && ren, char const * sansTTF, char const * serifTTF, char const * monoTTF) :
    renderer(std::move(ren)),
    sansFont(TTF_OpenFont(sansTTF, 24), &renderer),
    serifFont(TTF_OpenFont(serifTTF, 24), &renderer),
    monospaceFont(TTF_OpenFont(monoTTF, 24), &renderer)
{}

UISize RenderContext::measureString(const std::string & text, UIFont font, xstd::optional<int> line_width) const
{
    auto & fc = getFont(font);

    UISize size{0, 0};
    if (auto const rendered = fc.render(text); rendered) {
        size = rendered->size;
    }
    size.h = std::max(size.h, 24);
    return size;
}

Rectangle RenderContext::pushClipRect(const Rectangle & rect)
{
    assert(SDL_RenderIsClipEnabled(renderer));
    auto const currentClipRect = Rectangle(renderer.getClipRect());

    clip_rects.push(currentClipRect);

    Rectangle actual_clip_rect = Rectangle::intersect(currentClipRect, rect);

    renderer.setClipRect(actual_clip_rect);

    return actual_clip_rect;
}

void RenderContext::popClipRect()
{
    assert(clip_rects.size() > 0);

    renderer.setClipRect(clip_rects.top());
    clip_rects.pop();
}

void RenderContext::drawString(const std::string & text, const Rectangle & target, UIFont font, TextAlign align)
{
    auto & fc = getFont(font);

    if (auto const rendered = fc.render(text); rendered) {

        SDL_Rect dest = {target.x, target.y, rendered->size.w, rendered->size.h};

        switch (align) {
            case TextAlign::left:
                dest.x = target.x;
                break;
            case TextAlign::center:
                dest.x = target.x + (target.w - dest.w) / 2;
                break;
            case TextAlign::right:
                dest.x = target.x + target.w - dest.w;
                break;
            case TextAlign::block:
                dest.x = target.x;
                dest.w = target.w; // OUCH
                break;
        }

        pushClipRect(target);

        SDL_SetTextureColorMod(rendered->texture.get(), 0x00, 0x00, 0x00);
        renderer.copy(rendered->texture.get(), dest);

        popClipRect();
    }
}

FontCache & RenderContext::getFont(UIFont font) const
{
    switch (font) {
        case UIFont::sans:
            return sansFont;
        case UIFont::serif:
            return serifFont;
        case UIFont::monospace:
            return monospaceFont;
    }
    assert(false);
}

void RenderContext::drawRect(const Rectangle & rect, Bevel bevel)
{
    renderer.setColor(0x80, 0x80, 0x80, 0xFF);
    renderer.drawRect(rect);
}

void RenderContext::fillRect(const Rectangle & rect, Color color)
{
    SDL_Color c;
    switch (color) {
        case Color::highlight:
            c = SDL_Color{0x00, 0x00, 0x80, 0xFF};
            break;
        case Color::background:
            c = SDL_Color{0xd6, 0xd3, 0xce, 0xFF};
            break;
        case Color::input_field:
            c = SDL_Color{0xFF, 0xFF, 0xFF, 0xFF};
            break;
    }
    renderer.setColor(c);
    renderer.fillRect(rect);
}

void RenderContext::drawIcon(const Rectangle & rect, SDL_Texture * texture, xstd::optional<Rectangle> clip_rect)
{
    if (clip_rect) {
        renderer.copy(texture, rect, *clip_rect);
    } else {
        renderer.copy(texture, rect);
    }
}

void RenderContext::drawHLine(int startX, int startY, int width, LineStyle style)
{
    renderer.setColor(0x80, 0x80, 0x80, 0xFF);
    renderer.drawLine(startX, startY, startX + width - 1, startY);
}

void RenderContext::drawVLine(int startX, int startY, int height, LineStyle style)
{
    renderer.setColor(0x80, 0x80, 0x80, 0xFF);
    renderer.drawLine(startX, startY, startX, startY + height - 1);
}

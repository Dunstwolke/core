#include "rendercontext.hpp"

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

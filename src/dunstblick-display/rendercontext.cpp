#include "rendercontext.hpp"

#include <cassert>

RenderContext::RenderContext(PainterAPI * api) : api(api)
{
    assert(api != nullptr);
}

Rectangle RenderContext::pushClipRect(const Rectangle & rect)
{
    auto const currentClipRect = api->getClipRect(api);

    // fprintf(stderr,
    //         "current: %ld %ld %lu %lu\n",
    //         currentClipRect.x,
    //         currentClipRect.y,
    //         currentClipRect.w,
    //         currentClipRect.h);

    // fprintf(stderr, "applied: %ld %ld %lu %lu\n", rect.x, rect.y, rect.w, rect.h);

    clip_rects.push(currentClipRect);

    Rectangle actual_clip_rect = Rectangle::intersect(currentClipRect, rect);

    api->setClipRect(api, actual_clip_rect);

    // fprintf(stderr,
    //         "actual: %ld %ld %lu %lu\n",
    //         actual_clip_rect.x,
    //         actual_clip_rect.y,
    //         actual_clip_rect.w,
    //         actual_clip_rect.h);

    return actual_clip_rect;
}

void RenderContext::popClipRect()
{
    assert(clip_rects.size() > 0);
    api->setClipRect(api, clip_rects.top());
    clip_rects.pop();
}

UISize RenderContext::measureString(std::string const & text, UIFont font, xstd::optional<int> line_width) const
{
    return api->measureString(api,
                              reinterpret_cast<uint8_t const *>(text.c_str()),
                              text.size(),
                              font,
                              line_width.value_or(0));
}

void RenderContext::drawString(std::string const & text, Rectangle const & target, UIFont font, TextAlign align)
{
    api->drawString(api, reinterpret_cast<uint8_t const *>(text.c_str()), text.size(), target, font, align);
}

void RenderContext::drawRect(Rectangle const & rect, Bevel bevel)
{
    api->drawRectangle(api, rect, bevel);
}

void RenderContext::fillRect(Rectangle const & rect, Color color)
{
    api->fillRectangle(api, rect, color);
}

void RenderContext::drawIcon(Rectangle const & rect, Image * texture, xstd::optional<Rectangle> clip_rect)
{
    if (clip_rect) {
        api->drawIcon(api, texture, rect, &*clip_rect);
    } else {
        api->drawIcon(api, texture, rect, nullptr);
    }
}

void RenderContext::drawHLine(int startX, int startY, int width, LineStyle style)
{
    api->drawHLine(api, startX, startY, width, style);
}

void RenderContext::drawVLine(int startX, int startY, int height, LineStyle style)
{
    api->drawVLine(api, startX, startY, height, style);
}
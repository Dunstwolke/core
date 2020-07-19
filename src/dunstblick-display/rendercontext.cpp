#include "rendercontext.hpp"

#include <cassert>

Rectangle RenderContext::pushClipRect(const Rectangle & rect)
{
    assert(false and "not implemented yet");

    // auto const currentClipRect = Rectangle(renderer.getClipRect());

    // clip_rects.push(currentClipRect);

    // Rectangle actual_clip_rect = Rectangle::intersect(currentClipRect, rect);

    // renderer.setClipRect(actual_clip_rect);

    // return actual_clip_rect;
}

void RenderContext::popClipRect()
{
    assert(false and "not implemented yet");
    // assert(clip_rects.size() > 0);

    // renderer.setClipRect(clip_rects.top());
    // clip_rects.pop();
}

UISize RenderContext::measureString(std::string const & text, UIFont font, xstd::optional<int> line_width) const
{
    assert(false and "not implemented yet");
}

void RenderContext::drawString(std::string const & text, Rectangle const & target, UIFont font, TextAlign align)
{
    assert(false and "not implemented yet");
}

void RenderContext::drawRect(Rectangle const & rect, Bevel bevel)
{
    assert(false and "not implemented yet");
}

void RenderContext::fillRect(Rectangle const & rect, Color color)
{
    assert(false and "not implemented yet");
}

void RenderContext::drawIcon(Rectangle const & rect, SDL_Texture * texture, xstd::optional<Rectangle> clip_rect)
{
    assert(false and "not implemented yet");
}

void RenderContext::drawHLine(int startX, int startY, int width, LineStyle style)
{
    assert(false and "not implemented yet");
}

void RenderContext::drawVLine(int startX, int startY, int height, LineStyle style)
{
    assert(false and "not implemented yet");
}
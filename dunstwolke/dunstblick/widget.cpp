#include "widget.hpp"

#include <stdexcept>

////////////////////////////////////////////////////////////////////////////////
/// Stage 1:
/// Determine widget sizes

void Widget::updateWantedSize()
{
    for(auto & child : children)
        child->updateWantedSize();

    this->wanted_size = this->calculateWantedSize();
    // this->wanted_size.w += this->margins.totalHorizontal();
    // this->wanted_size.h += this->margins.totalVertical();
}

SDL_Size Widget::calculateWantedSize()
{
    SDL_Size size = { 0, 0 };
    for(auto & child : children)
    {
        size.w = std::max(size.w, child->wanted_size.w);
        size.h = std::max(size.h, child->wanted_size.h);
    }
    return size;
}

////////////////////////////////////////////////////////////////////////////////
/// Stage 2:
/// Layouting

void Widget::layout(SDL_Rect const & _bounds)
{
    SDL_Rect const bounds = {
        _bounds.x + margins.left,
        _bounds.y + margins.top,
        std::max(0, _bounds.w - margins.totalHorizontal()), // safety check against underflow
        std::max(0, _bounds.h - margins.totalVertical()),
    };

    SDL_Rect target;
    switch(horizontalAlignment)
    {
    case HAlignment::stretch:
        target.w = bounds.w;
        target.x = 0;
        break;
    case HAlignment::left:
        target.w = std::min(wanted_size.w, bounds.w);
        target.x = 0;
        break;
    case HAlignment::center:
        target.w = std::min(wanted_size.w, bounds.w);
        target.x = (bounds.w - target.w) / 2;
        break;
    case HAlignment::right:
        target.w = std::min(wanted_size.w, bounds.w);
        target.x = bounds.w - target.w;
        break;
    }
    target.x += bounds.x;

    switch(verticalAlignment)
    {
    case VAlignment::stretch:
        target.h = bounds.h;
        target.y = 0;
        break;
    case VAlignment::top:
        target.h = std::min(wanted_size.h, bounds.h);
        target.y = 0;
        break;
    case VAlignment::middle:
        target.h = std::min(wanted_size.h, bounds.h);
        target.y = (bounds.h - target.h) / 2;
        break;
    case VAlignment::bottom:
        target.h = std::min(wanted_size.h, bounds.h);
        target.y = bounds.h - target.h;
        break;
    }
    target.y += bounds.y;

    this->actual_bounds = target;

    SDL_Rect const childArea = {
        this->actual_bounds.x + this->paddings.left,
        this->actual_bounds.y + this->paddings.top,
        this->actual_bounds.w - this->paddings.totalHorizontal(),
        this->actual_bounds.h - this->paddings.totalVertical(),
    };

    this->layoutChildren(childArea);
}

void Widget::layoutChildren(SDL_Rect const & rect)
{

    for(auto & child : children)
        child->layout(rect);
}

////////////////////////////////////////////////////////////////////////////////
/// Stage 3:
/// Rendering

void Widget::paint(RenderContext & context)
{
    context.renderer.setClipRect(actual_bounds);

    context.renderer.setColor(0xFF, 0x00, 0xFF, 0x40);
    context.renderer.fillRect(actual_bounds);

    this->paintWidget(context, actual_bounds);
    context.renderer.resetClipRect();
    for(auto & child : children)
        child->paint(context);
}

void Widget::setProperty(UIProperty property, UIValue value)
{
    switch(property)
    {
    case UIProperty::verticalAlignment:   verticalAlignment   = VAlignment(std::get<uint8_t>(value)); break;
    case UIProperty::horizontalAlignment: horizontalAlignment = HAlignment(std::get<uint8_t>(value)); break;
    case UIProperty::visibility:          visibility          = Visibility(std::get<uint8_t>(value)); break;
    case UIProperty::margins:             margins             = std::get<UIMargin>(value); break;
    case UIProperty::paddings:            paddings            = std::get<UIMargin>(value); break;
    default:
        throw std::range_error("widget received unsupported property!");
    }
}

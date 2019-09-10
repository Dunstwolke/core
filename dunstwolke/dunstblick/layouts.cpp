#include "layouts.hpp"

/*******************************************************************************
 * Stack Layout                                                                *
 ******************************************************************************/

StackLayout::StackLayout(StackDirection dir) :
    Widget(),
    direction(dir)
{
}

void StackLayout::paintWidget(RenderContext &, const SDL_Rect &)
{
    // layouts don't have visuals
}

void StackLayout::layoutChildren(const SDL_Rect &_rect)
{
    if(direction == StackDirection::vertical)
    {
        SDL_Rect rect = _rect;
        for(auto & child : children)
        {
            rect.h = child->wanted_size_with_margins().h;
            child->layout(rect);
            rect.y += rect.h;
        }
    }
    else
    {
        SDL_Rect rect = _rect;
        for(auto & child : children)
        {
            rect.w = child->wanted_size_with_margins().w;
            child->layout(rect);
            rect.x += rect.w;
        }
    }
}

SDL_Size StackLayout::calculateWantedSize()
{
    if(direction == StackDirection::vertical)
    {
        SDL_Size size = { 0, 0 };
        for(auto & child : children)
        {
            size.w = std::max(size.w, child->wanted_size_with_margins().w);
            size.h += wanted_size_with_margins().h;
        }
        return size;
    }
    else
    {
        SDL_Size size = { 0, 0 };
        for(auto & child : children)
        {
            size.w += child->wanted_size_with_margins().w;
            size.h = std::max(size.h, child->wanted_size_with_margins().h);
        }
        return size;
    }
}

void StackLayout::setProperty(UIProperty property, UIValue value)
{
    switch(property)
    {
    case UIProperty::stackDirection: direction = StackDirection(std::get<uint8_t>(value)); break;
    default: return Widget::setProperty(property, value);
    }
}

/*******************************************************************************
 * Dock  Layout                                                                *
 ******************************************************************************/

void DockLayout::paintWidget(RenderContext &, const SDL_Rect &)
{
    // layouts don't have visuals
}

void DockLayout::layoutChildren(const SDL_Rect &_rect)
{
    if(children.size() == 0)
        return;

    SDL_Rect childArea = _rect; // will decrease for each child until last.
    for(size_t i = 0; i < children.size() - 1; i++)
    {
        auto const site = getDockSite(i);
        auto const childSize = children[i]->wanted_size_with_margins();
        switch(site)
        {
        case DockSite::top:
            children[i]->layout({
                childArea.x,
                childArea.y,
                childArea.w,
                childSize.h
            });
            childArea.y += childSize.h;
            childArea.h -= childSize.h;
            break;

        case DockSite::bottom:
            children[i]->layout({
                childArea.x,
                childArea.y + childArea.h - childSize.h,
                childArea.w,
                childSize.h
            });
            childArea.h -= childSize.h;
            break;

        case DockSite::left:
            children[i]->layout({
                childArea.x,
                childArea.y,
                childArea.w,
                childSize.h
            });
            childArea.x += childSize.w;
            childArea.w -= childSize.w;
            break;

        case DockSite::right:
            children[i]->layout({
                childArea.x + childArea.w - childSize.w,
                childArea.y,
                childArea.w,
                childSize.h
            });
            childArea.w -= childSize.w;
            break;
        }
    }

    children.back()->layout(childArea);
}

SDL_Size DockLayout::calculateWantedSize()
{
    if(children.size() == 0)
        return { 0, 0 };

    SDL_Size size = children.back()->wanted_size;

    size_t i = children.size() -1;
    while(i > 0)
    {
        i -= 1;
        auto site = getDockSite(i);
        switch(site)
        {
        case DockSite::left:
        case DockSite::right:
            // docking on either left or right side
            // will increase the width of the wanted size
            // and will max out the height
            size.w += children[i]->wanted_size_with_margins().w;
            size.h = std::max(size.h, children[i]->wanted_size_with_margins().h);
            break;

        case DockSite::top:
        case DockSite::bottom:
            // docking on either top or bottom side
            // will increase the height of the wanted size
            // and will max out the width
            size.w = std::max(size.w, children[i]->wanted_size_with_margins().w);
            size.h += children[i]->wanted_size_with_margins().h;
            break;
        }
    }
    return size;
}

DockSite DockLayout::getDockSite(size_t index) const
{
    if(index >= dockSites.size())
        return DockSite::top;
    else
        return dockSites.at(index);
}

void DockLayout::setDockSite(size_t index, DockSite site)
{
    dockSites.resize(children.size());
    dockSites.at(index) = site;
}

void DockLayout::setProperty(UIProperty property, UIValue value)
{
    switch(property)
    {
    case UIProperty::dockSites:
    {
        assert(false);
//        auto const num = stream.read_uint();
//        dockSites.resize(num);
//        for(size_t i = 0; i < num; i++)
//            dockSites[i] = stream.read_enum<DockSite>();
//        break;
    }
    default:
        Widget::setProperty(property, value);
        break;
    }
}

#include "layouts.hpp"

/*******************************************************************************
 * Stack Layout                                                                *
 ******************************************************************************/

StackLayout::StackLayout(StackDirection dir) :
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
            if(child->getActualVisibility() == Visibility::collapsed)
                continue;
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
            if(child->getActualVisibility() == Visibility::collapsed)
                continue;
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
            if(child->getActualVisibility() == Visibility::collapsed)
                continue;
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
            if(child->getActualVisibility() == Visibility::collapsed)
                continue;
            size.w += child->wanted_size_with_margins().w;
            size.h = std::max(size.h, child->wanted_size_with_margins().h);
        }
        return size;
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
        if(children[i]->getActualVisibility() == Visibility::collapsed)
            continue;
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
                childSize.w,
                childArea.h
            });
            childArea.x += childSize.w;
            childArea.w -= childSize.w;
            break;

        case DockSite::right:
            children[i]->layout({
                childArea.x + childArea.w - childSize.w,
                childArea.y,
                childSize.w,
                childArea.h
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

        if(children[i]->getActualVisibility() == Visibility::collapsed)
            continue;

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
    return children.at(index)->dockSite;
}

void DockLayout::setDockSite(size_t index, DockSite site)
{
    children.at(index)->dockSite = site;
}

SDL_Size TabLayout::calculateWantedSize()
{
    SDL_Size size = { 0, 0 };
    for(auto & child : children)
    {
        size.w = std::max(size.w, child->wanted_size_with_margins().w);
        size.h = std::max(size.h, child->wanted_size_with_margins().h);
    }
    size.h += 32;
    return size;
}

void TabLayout::layoutChildren(const SDL_Rect &childArea)
{
    auto area = childArea;
    area.y += 32;
    area.h -= 32;
    for(size_t index = 0; index < children.size(); index++)
    {
        if(children[index]->visibility == Visibility::visible)
            children[index]->hidden_by_layout = (index != size_t(selectedIndex.value));
        else
            children[index]->hidden_by_layout = false;
        children[index]->layout(area);
    }
}

void TabLayout::paintWidget(RenderContext & context, const SDL_Rect & rectangle)
{
    auto & ren = context.renderer;

    ren.setColor(0x30, 0x30, 0x30);
    ren.fillRect(rectangle);

    SDL_Rect tab {
        rectangle.x,
        rectangle.y,
        0,
        32,
    };

    for(size_t index = 0; index < children.size(); index++)
    {
        if(not children[index]->hidden_by_layout and children[index]->getActualVisibility() != Visibility::visible)
            continue;

        auto * tex = context.getFont(UIFont::sans).render(children[index]->tabTitle);

        int w = 0, h = 0;
        if(tex != nullptr) {
            SDL_QueryTexture(tex, nullptr, nullptr, &w, &h);
        }
        tab.w = w + 8;

        if(index == gsl::narrow<size_t>(selectedIndex.value))
            ren.setColor(0x30, 0x30, 0x60);
        else
            ren.setColor(0x30, 0x30, 0x30);
        ren.fillRect(tab);

        if(tex != nullptr) {
            ren.copy(tex, {
                tab.x + 4,
                tab.y + (tab.h - h) / 2,
                w,
                h
            });
        }

        ren.setColor(0xFF, 0xFF, 0xFF);
        ren.drawRect(tab);

        tab.x += tab.w;
    }



    ren.setColor(0xFF, 0xFF, 0xFF);
    ren.drawRect(rectangle);
}

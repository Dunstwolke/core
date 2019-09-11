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

void GridLayout::paintWidget(RenderContext &, const SDL_Rect &)
{
    /* wellp */
}

void GridLayout::layoutChildren(const SDL_Rect &childArea)
{
    auto calculate_sizes = [](std::vector<int> & sizes, UISizeList const & list, int availableSize)
    {
        int rest = availableSize;

        int col_expander_count = 0;
        for(size_t i = 0; i < list.size(); i++)
        {
            size_t const idx = list[i].index();
            if(idx == 3) // percentage
                sizes[i] = int(std::get<float>(list[i]) * availableSize); // adjust to available size
            if(idx != 1) // expand
                rest -= sizes[i]; // calculate remaining size for all expanders
            else
                col_expander_count += 1;
        }
        // now fill up to actual count
        for(size_t i = list.size(); i < sizes.size(); i++)
            rest -= sizes[i];

        if(rest < 0)
            rest = 0;

        for(size_t i = 0; i < list.size(); i++)
        {
            if(list[i].index() == 1) // expand
                sizes[i] = rest / col_expander_count; // adjust expanded columns
        }
    };

    calculate_sizes(column_widths, columns, childArea.w);
    calculate_sizes(row_heights, rows, childArea.h);

    size_t row = 0;
    size_t col = 0;

    SDL_Rect cursor = {
        childArea.x,
        childArea.y,
        0, 0
    };

    size_t index;
    for(index = 0; index < children.size(); index++)
    {
        children[index]->hidden_by_layout = false;
        if(children[index]->visibility == Visibility::collapsed)
            continue;

        cursor.w = column_widths[col];
        cursor.h = row_heights[row];

        children[index]->layout(cursor);

        cursor.x += cursor.w;

        col += 1;
        if(col >= column_widths.size()) {
            cursor.x = childArea.x;
            cursor.y += cursor.h;
            row += 1;
            col = 0;
            if(row >= row_heights.size()) {
                index++; // must be manually incremented here
                         // otherwise the last visible element will be
                         // hidden by the next loop
                break; // we are *full*
            }
        }
    }
    for(/* from previous loop */; index < children.size(); index++)
    {
        children[index]->hidden_by_layout = true;
    }
}

SDL_Size GridLayout::calculateWantedSize()
{
    row_heights.resize(getRowCount());
    column_widths.resize(getColumnCount());

    size_t row = 0;
    size_t col = 0;
    for(auto & child : children)
    {
        if(child->visibility == Visibility::collapsed)
            continue;

        auto const childSize = child->wanted_size_with_margins();

        column_widths[col] = std::max(column_widths[col], childSize.w);
        row_heights[row] = std::max(row_heights[row], childSize.h);

        col += 1;
        if(col >= column_widths.size()) {
            row += 1;
            col = 0;
            if(row >= row_heights.size())
                break; // we are *full*
        }
    }

    for(size_t i = 0; i < columns->size(); i++)
    {
        if(columns.value[i].index() == 2) // absolute column
            column_widths[i] = std::get<int>(columns.value[i]);
    }

    for(size_t i = 0; i < rows->size(); i++)
    {
        if(rows.value[i].index() == 2) // absolute column
            row_heights[i] = std::get<int>(rows.value[i]);
    }

    return {
        std::accumulate(column_widths.begin(), column_widths.end(), 0),
        std::accumulate(row_heights.begin(), row_heights.end(), 0),
    };
}

size_t GridLayout::getRowCount() const
{
    if(rows->size() != 0)
        return rows->size();
    else
        return (children.size() + columns->size() - 1) / columns->size();
}

size_t GridLayout::getColumnCount() const
{
    if(columns->size() != 0)
        return columns->size();
    else
        return (children.size() + rows->size() - 1) / rows->size();
}

void CanvasLayout::paintWidget(RenderContext &, const SDL_Rect &)
{

}

void CanvasLayout::layoutChildren(const SDL_Rect &childArea)
{
    for(auto & child : this->children)
    {
        child->layout({
            childArea.x + child->left,
            childArea.y +child->top,
            child->wanted_size_with_margins().w,
            child->wanted_size_with_margins().h,
        });
    }
}

SDL_Size CanvasLayout::calculateWantedSize()
{
    SDL_Size size = { 0, 0 };
    for(auto & child : this->children)
    {
        auto cs = child->wanted_size_with_margins();
        size.w = std::max(size.w, child->left + cs.w);
        size.h = std::max(size.h, child->top + cs.h);
    }
    return size;
}

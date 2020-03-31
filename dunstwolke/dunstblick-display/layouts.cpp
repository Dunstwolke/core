#include "layouts.hpp"

/*******************************************************************************
 * Stack Layout                                                                *
 ******************************************************************************/

StackLayout::StackLayout(StackDirection dir) : direction(dir) {}

void StackLayout::layoutChildren(const Rectangle & _rect)
{
    if (direction.get(this) == StackDirection::vertical) {
        Rectangle rect = _rect;
        for (auto & child : children) {
            if (child->getActualVisibility() == Visibility::collapsed)
                continue;
            rect.h = child->wanted_size_with_margins().h;
            child->layout(rect);
            rect.y += rect.h;
        }
    } else {
        Rectangle rect = _rect;
        for (auto & child : children) {
            if (child->getActualVisibility() == Visibility::collapsed)
                continue;
            rect.w = child->wanted_size_with_margins().w;
            child->layout(rect);
            rect.x += rect.w;
        }
    }
}

UISize StackLayout::calculateWantedSize(IWidgetPainter const &)
{
    UISize size = {0, 0};
    if (direction.get(this) == StackDirection::vertical) {
        for (auto & child : children) {
            if (child->getActualVisibility() == Visibility::collapsed)
                continue;
            size.w = std::max(size.w, child->wanted_size_with_margins().w);
            size.h += child->wanted_size_with_margins().h;
        }
    } else {
        for (auto & child : children) {
            if (child->getActualVisibility() == Visibility::collapsed)
                continue;
            size.w += child->wanted_size_with_margins().w;
            size.h = std::max(size.h, child->wanted_size_with_margins().h);
        }
    }
    size.w += paddings.get(this).totalHorizontal();
    size.h += paddings.get(this).totalVertical();
    return size;
}

/*******************************************************************************
 * Dock  Layout                                                                *
 ******************************************************************************/

void DockLayout::layoutChildren(const Rectangle & _rect)
{
    if (children.size() == 0)
        return;

    Rectangle childArea = _rect; // will decrease for each child until last.
    for (size_t i = 0; i < children.size() - 1; i++) {
        if (children[i]->getActualVisibility() == Visibility::collapsed)
            continue;
        auto const site = getDockSite(i);
        auto const childSize = children[i]->wanted_size_with_margins();
        switch (site) {
            case DockSite::top:
                children[i]->layout({childArea.x, childArea.y, childArea.w, childSize.h});
                childArea.y += childSize.h;
                childArea.h -= childSize.h;
                break;

            case DockSite::bottom:
                children[i]->layout({childArea.x, childArea.y + childArea.h - childSize.h, childArea.w, childSize.h});
                childArea.h -= childSize.h;
                break;

            case DockSite::left:
                children[i]->layout({childArea.x, childArea.y, childSize.w, childArea.h});
                childArea.x += childSize.w;
                childArea.w -= childSize.w;
                break;

            case DockSite::right:
                children[i]->layout({childArea.x + childArea.w - childSize.w, childArea.y, childSize.w, childArea.h});
                childArea.w -= childSize.w;
                break;
        }
    }

    children.back()->layout(childArea);
}

UISize DockLayout::calculateWantedSize(IWidgetPainter const &)
{
    if (children.size() == 0)
        return {0, 0};

    UISize size = children.back()->wanted_size_with_margins();

    size_t i = children.size() - 1;
    while (i > 0) {
        i -= 1;

        if (children[i]->getActualVisibility() == Visibility::collapsed)
            continue;

        auto site = getDockSite(i);
        switch (site) {
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
    return children.at(index)->dockSite.get(this);
}

void DockLayout::setDockSite(size_t index, DockSite site)
{
    children.at(index)->dockSite.set(this, site);
}

UISize TabLayout::calculateWantedSize(IWidgetPainter const & painter)
{
    UISize size = {0, 0};
    for (auto & child : children) {
        size.w = std::max(size.w, child->wanted_size_with_margins().w);
        size.h = std::max(size.h, child->wanted_size_with_margins().h);
    }
    size.h += 32;

    tabButtons.resize(children.size());
    for (size_t i = 0; i < children.size(); i++) {
        auto const text_size = painter.measureString(children.at(i)->tabTitle.get(this), UIFont::sans, xstd::nullopt);

        tabButtons.at(i) = Rectangle{
            0,
            0,
            text_size.w + 8,
            32,
        };
    }

    return size;
}

bool TabLayout::processEvent(const SDL_Event & event)
{
    if (event.type != SDL_MOUSEBUTTONDOWN)
        return false;
    for (size_t i = 0; i < tabButtons.size(); i++) {
        if (tabButtons.at(i).contains(event.button.x, event.button.y)) {
            selectedIndex.set(this, gsl::narrow<int>(i));
            return true;
        }
    }
    return false;
}

SDL_SystemCursor TabLayout::getCursor(const UIPoint & p) const
{
    for (auto const & rect : tabButtons) {
        if (rect.contains(p))
            return SDL_SYSTEM_CURSOR_HAND;
    }
    return SDL_SYSTEM_CURSOR_ARROW;
}

void TabLayout::layoutChildren(const Rectangle & childArea)
{
    auto const selected_index = gsl::narrow<size_t>(selectedIndex.get(this));
    if (children.size() > 0 and selected_index >= children.size()) {
        selectedIndex.set(this, gsl::narrow<int>(children.size() - 1));
    }

    auto area = childArea;
    area.y += 32;
    area.h -= 32;
    for (size_t index = 0; index < children.size(); index++) {
        if (children[index]->visibility.get(this) == Visibility::visible)
            children[index]->hidden_by_layout = (index != size_t(selectedIndex.get(this)));
        else
            children[index]->hidden_by_layout = false;
        children[index]->layout(area);
    }

    int dx = 0;
    assert(children.size() == tabButtons.size());
    for (size_t i = 0; i < children.size(); i++) {
        tabButtons.at(i).x = childArea.x + dx;
        tabButtons.at(i).y = childArea.y;
        dx += tabButtons.at(i).w;
    }
}

void TabLayout::paintWidget(IWidgetPainter & ren, const Rectangle & rectangle)
{
    ren.fillRect(rectangle, Color::background);

    Rectangle topbar = rectangle;
    topbar.h = 32;

    Rectangle content = rectangle;
    content.y += 32;
    content.h -= 32;

    // TODO: Impove tab rendering
    ren.fillRect(topbar, Color::input_field);

    auto const selected_index = gsl::narrow<size_t>(selectedIndex.get(this));

    assert(children.size() == tabButtons.size());
    for (size_t index = 0; index < children.size(); index++) {
        if (not children[index]->hidden_by_layout and children[index]->getActualVisibility() != Visibility::visible)
            continue;

        auto const tab = tabButtons[index];

        ren.fillRect(tab, Color::background);

        auto const title = children[index]->tabTitle.get(this);

        if (not title.empty()) {
            ren.drawString(title, tab, UIFont::sans, TextAlign::center);
        }

        if (index == selected_index)
            ren.drawRect(tab, Bevel::sunken);
        else
            ren.drawRect(tab, Bevel::crease);
    }

    ren.drawRect(content, Bevel::sunken);
}

void GridLayout::layoutChildren(const Rectangle & childArea)
{
    auto calculate_sizes = [](std::vector<int> & sizes, UISizeList const & list, int availableSize) {
        int rest = availableSize;

        int col_expander_count = 0;
        for (size_t i = 0; i < list.size(); i++) {
            size_t const idx = list[i].index();
            if (idx == 3)                                                 // percentage
                sizes[i] = int(std::get<float>(list[i]) * availableSize); // adjust to available size
            if (idx != 1)                                                 // expand
                rest -= sizes[i];                                         // calculate remaining size for all expanders
            else
                col_expander_count += 1;
        }
        // now fill up to actual count
        for (size_t i = list.size(); i < sizes.size(); i++)
            rest -= sizes[i];

        if (rest < 0)
            rest = 0;

        for (size_t i = 0; i < list.size(); i++) {
            if (list[i].index() == 1)                 // expand
                sizes[i] = rest / col_expander_count; // adjust expanded columns
        }
    };

    calculate_sizes(column_widths, columns.get(this), childArea.w);
    calculate_sizes(row_heights, rows.get(this), childArea.h);

    size_t row = 0;
    size_t col = 0;

    Rectangle cursor = {childArea.x, childArea.y, 0, 0};

    size_t index;
    for (index = 0; index < children.size(); index++) {
        children[index]->hidden_by_layout = false;
        if (children[index]->visibility.get(this) == Visibility::collapsed)
            continue;

        cursor.w = column_widths[col];
        cursor.h = row_heights[row];

        children[index]->layout(cursor);

        cursor.x += cursor.w;

        col += 1;
        if (col >= column_widths.size()) {
            cursor.x = childArea.x;
            cursor.y += cursor.h;
            row += 1;
            col = 0;
            if (row >= row_heights.size()) {
                index++; // must be manually incremented here
                         // otherwise the last visible element will be
                         // hidden by the next loop
                break;   // we are *full*
            }
        }
    }
    for (/* from previous loop */; index < children.size(); index++) {
        children[index]->hidden_by_layout = true;
    }
}

UISize GridLayout::calculateWantedSize(IWidgetPainter const &)
{
    row_heights.resize(getRowCount());
    column_widths.resize(getColumnCount());

    size_t row = 0;
    size_t col = 0;
    for (auto & child : children) {
        if (child->visibility.get(this) == Visibility::collapsed)
            continue;

        auto const childSize = child->wanted_size_with_margins();

        column_widths[col] = std::max(column_widths[col], childSize.w);
        row_heights[row] = std::max(row_heights[row], childSize.h);

        col += 1;
        if (col >= column_widths.size()) {
            row += 1;
            col = 0;
            if (row >= row_heights.size())
                break; // we are *full*
        }
    }

    for (size_t i = 0; i < columns.get(this).size(); i++) {
        if (columns.get(this)[i].index() == 2) // absolute column
            column_widths[i] = std::get<int>(columns.get(this)[i]);
    }

    for (size_t i = 0; i < rows.get(this).size(); i++) {
        if (rows.get(this)[i].index() == 2) // absolute column
            row_heights[i] = std::get<int>(rows.get(this)[i]);
    }

    return {
        std::accumulate(column_widths.begin(), column_widths.end(), 0),
        std::accumulate(row_heights.begin(), row_heights.end(), 0),
    };
}

size_t GridLayout::getRowCount() const
{
    if (rows.get(this).size() != 0)
        return rows.get(this).size();
    else
        return (children.size() + columns.get(this).size() - 1) / columns.get(this).size();
}

size_t GridLayout::getColumnCount() const
{
    if (columns.get(this).size() != 0)
        return columns.get(this).size();
    else
        return (children.size() + rows.get(this).size() - 1) / rows.get(this).size();
}

void CanvasLayout::layoutChildren(const Rectangle & childArea)
{
    for (auto & child : this->children) {
        if (child->visibility.get(this) == Visibility::collapsed)
            continue;
        child->layout({
            childArea.x + child->left.get(this),
            childArea.y + child->top.get(this),
            child->wanted_size_with_margins().w,
            child->wanted_size_with_margins().h,
        });
    }
}

UISize CanvasLayout::calculateWantedSize(IWidgetPainter const &)
{
    UISize size = {0, 0};
    for (auto & child : this->children) {
        if (child->visibility.get(this) == Visibility::collapsed)
            continue;
        auto cs = child->wanted_size_with_margins();
        size.w = std::max(size.w, child->left.get(this) + cs.w);
        size.h = std::max(size.h, child->top.get(this) + cs.h);
    }
    return size;
}

void FlowLayout::layoutChildren(const Rectangle & childArea)
{
    Rectangle rect{childArea.x, childArea.y, 0, 0};
    int max_h = 0;
    size_t i;
    bool first_in_line = true;
    for (i = 0; i < children.size(); i++) {
        if (children[i]->visibility.get(this) == Visibility::collapsed)
            continue;
        auto size = children[i]->wanted_size_with_margins();
        rect.w = size.w;
        rect.h = size.h;

        if (not first_in_line and rect.x + rect.w >= childArea.x + childArea.w) {
            // break here
            rect.x = childArea.x;
            rect.y += max_h;
            max_h = 0;
            first_in_line = true;
            if (rect.y >= childArea.y + childArea.h) {
                i += 1;
                break;
            }
        }

        children[i]->layout(rect);
        first_in_line = false;

        rect.x += rect.w;

        max_h = std::max(max_h, rect.h);

        if (rect.x >= childArea.x + childArea.w) {
            rect.x = childArea.x;
            rect.y += max_h;
            max_h = 0;
            first_in_line = true;
            if (rect.y >= childArea.y + childArea.h) {
                i += 1;
                break;
            }
        }
    }
    for (/* i = from previous loop */; i < children.size(); i++) {
        children[i]->hidden_by_layout = true;
    }
}

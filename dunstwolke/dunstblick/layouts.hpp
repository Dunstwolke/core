#ifndef LAYOUTS_HPP
#define LAYOUTS_HPP

#include "widget.hpp"

struct StackLayout : WidgetIs<UIWidget::stack_layout>
{
    property<StackDirection> direction;

    explicit StackLayout(StackDirection dir = StackDirection::vertical);

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;
};

struct DockLayout : WidgetIs<UIWidget::dock_layout>
{
    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;

    DockSite getDockSite(size_t index) const;

    void setDockSite(size_t index, DockSite site);
};


struct TabLayout : WidgetIs<UIWidget::tab_layout>
{
    property<int> selectedIndex = 0;

    void paintWidget(const SDL_Rect &) override;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;
};

struct GridLayout : WidgetIs<UIWidget::grid_layout>
{
    property<UISizeList> rows;
    property<UISizeList> columns;

    // gets calculated in calculateWantedSize
    // and gets used in layoutChildren
    // both store
    std::vector<int> row_heights, column_widths;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;

    size_t getRowCount() const;
    size_t getColumnCount() const;
};


struct CanvasLayout : WidgetIs<UIWidget::canvas_layout>
{
    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;
};

struct FlowLayout : WidgetIs<UIWidget::flow_layout>
{
    property<SDL_Size> sizeHint = SDL_Size { 256, 256 };

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;
};


#endif // LAYOUTS_HPP

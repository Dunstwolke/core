#ifndef LAYOUTS_HPP
#define LAYOUTS_HPP

#include "widget.hpp"

struct StackLayout : WidgetIs<UIWidget::stack_layout>
{
    property<StackDirection> direction;

    explicit StackLayout(StackDirection dir = StackDirection::vertical);

    void layoutChildren(Rectangle const & childArea) override;

    UISize calculateWantedSize(IWidgetPainter const &) override;
};

struct DockLayout : WidgetIs<UIWidget::dock_layout>
{
    void layoutChildren(Rectangle const & childArea) override;

    UISize calculateWantedSize(IWidgetPainter const &) override;

    DockSite getDockSite(size_t index) const;

    void setDockSite(size_t index, DockSite site);
};

struct TabLayout : WidgetIs<UIWidget::tab_layout>
{
    property<int> selectedIndex = 0;

    std::vector<Rectangle> tabButtons;

    void paintWidget(IWidgetPainter & painter, const Rectangle &) override;

    void layoutChildren(Rectangle const & childArea) override;

    UISize calculateWantedSize(IWidgetPainter const & painter) override;

    virtual bool processEvent(SDL_Event const & event) override;

    virtual SDL_SystemCursor getCursor(UIPoint const & p) const override;
};

struct GridLayout : WidgetIs<UIWidget::grid_layout>
{
    property<UISizeList> rows;
    property<UISizeList> columns;

    // gets calculated in calculateWantedSize
    // and gets used in layoutChildren
    // both store
    std::vector<size_t> row_heights, column_widths;

    void layoutChildren(Rectangle const & childArea) override;

    UISize calculateWantedSize(IWidgetPainter const &) override;

    size_t getRowCount() const;
    size_t getColumnCount() const;
};

struct CanvasLayout : WidgetIs<UIWidget::canvas_layout>
{
    void layoutChildren(Rectangle const & childArea) override;

    UISize calculateWantedSize(IWidgetPainter const &) override;
};

struct FlowLayout : WidgetIs<UIWidget::flow_layout>
{
    void layoutChildren(Rectangle const & childArea) override;
};

#endif // LAYOUTS_HPP

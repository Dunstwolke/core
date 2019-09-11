#ifndef LAYOUTS_HPP
#define LAYOUTS_HPP

#include "widget.hpp"

struct StackLayout : WidgetIs<UIWidget::stack_layout>
{
    property<StackDirection> direction;

    explicit StackLayout(StackDirection dir = StackDirection::vertical);

    void paintWidget(RenderContext &, const SDL_Rect &) override;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;
};

struct DockLayout : WidgetIs<UIWidget::dock_layout>
{
    void paintWidget(RenderContext &, const SDL_Rect &) override;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;

    DockSite getDockSite(size_t index) const;

    void setDockSite(size_t index, DockSite site);
};


struct TabLayout : WidgetIs<UIWidget::tab_layout>
{
    property<int> selectedIndex = 0;

    void paintWidget(RenderContext &, const SDL_Rect &) override;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;
};

#define CanvasLayout StackLayout
#define FlowLayout StackLayout
#define GridLayout StackLayout


#endif // LAYOUTS_HPP

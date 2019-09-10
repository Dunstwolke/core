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
    std::vector<DockSite> dockSites;

    void paintWidget(RenderContext &, const SDL_Rect &) override;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;

    DockSite getDockSite(size_t index) const;

    void setDockSite(size_t index, DockSite site);
};



#endif // LAYOUTS_HPP

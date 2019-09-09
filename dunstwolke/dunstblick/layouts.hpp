#ifndef LAYOUTS_HPP
#define LAYOUTS_HPP

#include "widget.hpp"

struct StackLayout : Widget
{
    StackDirection direction;

    explicit StackLayout(StackDirection dir = StackDirection::vertical);

    void paintWidget(sdl2::renderer &, const SDL_Rect &) override;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;

    void deserialize_property(UIProperty property, InputStream &stream) override;
};

struct DockLayout : Widget
{
    std::vector<DockSite> dockSites;

    void paintWidget(sdl2::renderer &, const SDL_Rect &) override;

    void layoutChildren(SDL_Rect const & childArea) override;

    SDL_Size calculateWantedSize() override;

    DockSite getDockSite(size_t index) const;

    void setDockSite(size_t index, DockSite site);

    void deserialize_property(UIProperty property, InputStream &stream) override;
};



#endif // LAYOUTS_HPP

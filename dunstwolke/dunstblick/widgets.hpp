#ifndef WIDGETS_HPP
#define WIDGETS_HPP

#include "widget.hpp"

struct Spacer : Widget
{
    SDL_Size sizeHint = { 0, 0 };

    SDL_Size calculateWantedSize() override;

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;

    void setProperty(UIProperty property, UIValue value) override;
};

struct Button : Widget
{
    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};

struct Label : Widget
{
    std::string text = "";
    UIFont font = UIFont::sans;

    explicit Label();

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;

    SDL_Size calculateWantedSize() override;

    void setProperty(UIProperty property, UIValue value) override;
};

#endif // WIDGETS_HPP

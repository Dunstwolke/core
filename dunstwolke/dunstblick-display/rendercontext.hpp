#ifndef RENDERCONTEXT_HPP
#define RENDERCONTEXT_HPP

#include "fontcache.hpp"
#include "widget.hpp"
#include <sdl2++/renderer>
#include <stack>

struct RenderContext : IWidgetPainter
{
    sdl2::renderer renderer;
    mutable FontCache sansFont;
    mutable FontCache serifFont;
    mutable FontCache monospaceFont;
    std::stack<Rectangle> clip_rects;

    explicit RenderContext(sdl2::renderer && ren, char const * sansTTF, char const * serifTTF, char const * monoTTF);

    FontCache & getFont(UIFont) const;

    UISize measureString(std::string const & text, UIFont font, xstd::optional<int> line_width) const override;

    void drawString(std::string const & text, Rectangle const & target, UIFont font, TextAlign align) override;

    void drawRect(Rectangle const & rect, Bevel bevel) override;

    void fillRect(Rectangle const & rect, Color color) override;

    void drawIcon(Rectangle const & rect, SDL_Texture * texture, xstd::optional<Rectangle> clip_rect) override;

    void drawHLine(int startX, int startY, int width, LineStyle style) override;

    void drawVLine(int startX, int startY, int height, LineStyle style) override;

    Rectangle pushClipRect(Rectangle const & rect) override;

    void popClipRect() override;
};

#endif // RENDERCONTEXT_HPP

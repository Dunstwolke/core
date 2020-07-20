#ifndef RENDERCONTEXT_HPP
#define RENDERCONTEXT_HPP

#include "widget.hpp"
#include <stack>

/// Keep in sync with
/// painting.zig
struct PainterAPI
{
    void __attribute__((cdecl)) (*fillRectangle)(PainterAPI * self, Rectangle rectangle, Color color);
    void __attribute__((cdecl)) (*drawRectangle)(PainterAPI * self, Rectangle rect, Bevel bevel);
    void __attribute__((cdecl)) (*drawHLine)(PainterAPI * self, ssize_t x0, ssize_t y0, size_t width, LineStyle style);
    void __attribute__((cdecl)) (*drawVLine)(PainterAPI * self, ssize_t x0, ssize_t y0, size_t height, LineStyle style);
    void __attribute__((cdecl)) (*drawIcon)(PainterAPI * self, Image * icon, Rectangle rectangle);
    UISize __attribute__((cdecl)) (*measureString)(
        PainterAPI * self, uint8_t const * text, size_t text_len, UIFont font, size_t line_width);
    void __attribute__((cdecl)) (*drawString)(
        PainterAPI * self, uint8_t const * text, size_t text_len, Rectangle target, UIFont font, TextAlign alignment);
    void __attribute__((cdecl)) (*setClipRect)(PainterAPI * self, Rectangle rect);
    void __attribute__((cdecl)) (*resetClipRect)(PainterAPI * self);
    Rectangle __attribute__((cdecl)) (*getClipRect)(PainterAPI * self);
};

struct RenderContext : IWidgetPainter
{
    PainterAPI * api;

    explicit RenderContext(PainterAPI * api);

    std::stack<Rectangle> clip_rects;

    UISize measureString(std::string const & text, UIFont font, xstd::optional<int> line_width) const override;

    void drawString(std::string const & text, Rectangle const & target, UIFont font, TextAlign align) override;

    void drawRect(Rectangle const & rect, Bevel bevel) override;

    void fillRect(Rectangle const & rect, Color color) override;

    void drawIcon(Rectangle const & rect, Image * texture, xstd::optional<Rectangle> clip_rect) override;

    void drawHLine(int startX, int startY, int width, LineStyle style) override;

    void drawVLine(int startX, int startY, int height, LineStyle style) override;

    Rectangle pushClipRect(Rectangle const & rect) override;

    void popClipRect() override;
};

#endif // RENDERCONTEXT_HPP

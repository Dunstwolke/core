#ifndef RENDERCONTEXT_HPP
#define RENDERCONTEXT_HPP

#include "widget.hpp"
#include <stack>

#define EXTERN __attribute__((cdecl))

/// Keep in sync with
/// painting.zig
struct PainterAPI
{
    void EXTERN (*fillRectangle)(PainterAPI * self, Rectangle rectangle, Color color);
    void EXTERN (*drawRectangle)(PainterAPI * self, Rectangle rect, Bevel bevel);
    void EXTERN (*drawHLine)(PainterAPI * self, ssize_t x0, ssize_t y0, size_t width, LineStyle style);
    void EXTERN (*drawVLine)(PainterAPI * self, ssize_t x0, ssize_t y0, size_t height, LineStyle style);
    void EXTERN (*drawIcon)(PainterAPI * self, Image * icon, Rectangle target, Rectangle const * source);
    UISize EXTERN (*measureString)(
        PainterAPI * self, uint8_t const * text, size_t text_len, UIFont font, size_t line_width);
    void EXTERN (*drawString)(
        PainterAPI * self, uint8_t const * text, size_t text_len, Rectangle target, UIFont font, TextAlign alignment);
    void EXTERN (*setClipRect)(PainterAPI * self, Rectangle rect);
    void EXTERN (*resetClipRect)(PainterAPI * self);
    Rectangle EXTERN (*getClipRect)(PainterAPI * self);
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

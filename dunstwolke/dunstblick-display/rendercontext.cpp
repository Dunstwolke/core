#include "rendercontext.hpp"

auto constexpr color_highlight = SDL_Color{0x00, 0x00, 0x80, 0xFF};
auto constexpr color_background = SDL_Color{0xd6, 0xd3, 0xce, 0xFF};
auto constexpr color_input_field = SDL_Color{0xFF, 0xFF, 0xFF, 0xFF};
auto constexpr color_checker = SDL_Color{0xec, 0xeb, 0xe9, 0xFF};

auto constexpr color_3d_bright = SDL_Color{0xFF, 0xFF, 0xFF, 0xFF};
auto constexpr color_3d_medium = SDL_Color{0x84, 0x82, 0x84, 0xFF};
auto constexpr color_3d_dark = SDL_Color{0x42, 0x41, 0x42, 0xFF};
auto constexpr color_3d_black = SDL_Color{0x00, 0x00, 0x00, 0xFF};

RenderContext::RenderContext(sdl2::renderer && ren, char const * sansTTF, char const * serifTTF, char const * monoTTF) :
    renderer(std::move(ren)),
    sansFont(TTF_OpenFont(sansTTF, 24), &renderer),
    serifFont(TTF_OpenFont(serifTTF, 24), &renderer),
    monospaceFont(TTF_OpenFont(monoTTF, 24), &renderer)
{}

UISize RenderContext::measureString(const std::string & text, UIFont font, xstd::optional<int> line_width) const
{
    auto & fc = getFont(font);

    UISize size{0, 0};
    if (auto const rendered = fc.render(text); rendered) {
        size = rendered->size;
    }
    size.h = std::max(size.h, 24);
    return size;
}

Rectangle RenderContext::pushClipRect(const Rectangle & rect)
{
    assert(SDL_RenderIsClipEnabled(renderer));
    auto const currentClipRect = Rectangle(renderer.getClipRect());

    clip_rects.push(currentClipRect);

    Rectangle actual_clip_rect = Rectangle::intersect(currentClipRect, rect);

    renderer.setClipRect(actual_clip_rect);

    return actual_clip_rect;
}

void RenderContext::popClipRect()
{
    assert(clip_rects.size() > 0);

    renderer.setClipRect(clip_rects.top());
    clip_rects.pop();
}

void RenderContext::drawString(const std::string & text, const Rectangle & target, UIFont font, TextAlign align)
{
    auto & fc = getFont(font);

    if (auto const rendered = fc.render(text); rendered) {

        SDL_Rect dest = {target.x, target.y, rendered->size.w, rendered->size.h};

        switch (align) {
            case TextAlign::left:
                dest.x = target.x;
                break;
            case TextAlign::center:
                dest.x = target.x + (target.w - dest.w) / 2;
                break;
            case TextAlign::right:
                dest.x = target.x + target.w - dest.w;
                break;
            case TextAlign::block:
                dest.x = target.x;
                dest.w = target.w; // OUCH
                break;
        }

        pushClipRect(target);

        SDL_SetTextureColorMod(rendered->texture.get(), 0x00, 0x00, 0x00);
        renderer.copy(rendered->texture.get(), dest);

        popClipRect();
    }
}

FontCache & RenderContext::getFont(UIFont font) const
{
    switch (font) {
        case UIFont::sans:
            return sansFont;
        case UIFont::serif:
            return serifFont;
        case UIFont::monospace:
            return monospaceFont;
    }
    assert(false);
}

void RenderContext::drawRectImpl(const Rectangle & rect, const SDL_Color & top_left, const SDL_Color & bottom_right)
{
    int const l = rect.x;
    int const t = rect.y;
    int const r = rect.x + rect.w - 1;
    int const b = rect.y + rect.h - 1;

    renderer.setColor(top_left);
    renderer.drawLine(l, t, r - 1, t);
    renderer.drawLine(l, t, l, b - 1);

    renderer.setColor(bottom_right);
    renderer.drawLine(l, b, r, b);
    renderer.drawLine(r, t, r, b);
}

//    edge,           ///< A small border with a 3D effect, looks like a welding around the object
//    crease,         ///< A small border with a 3D effect, looks like a crease around the object
//    raised,         ///< A small border with a 3D effect, looks like the object is raised up from the surroundings
//    sunken,         ///< A small border with a 3D effect, looks like the object is sunken into the surroundings
//    input_field,    ///< The *deep* 3D border
//    button_default, ///< Normal button outline
//    button_pressed, ///< Pressed button outline
//    button_active,  ///< Active button outline, not pressed
void RenderContext::drawRect(const Rectangle & rect, Bevel bevel)
{
    switch (bevel) {
        case Bevel::edge:
            drawRectImpl(rect, color_3d_bright, color_3d_medium);
            drawRectImpl(rect.shrink(1), color_3d_medium, color_3d_bright);
            break;
        case Bevel::crease:
            drawRectImpl(rect, color_3d_medium, color_3d_bright);
            drawRectImpl(rect.shrink(1), color_3d_bright, color_3d_medium);
            break;

        case Bevel::raised:
            drawRectImpl(rect, color_3d_bright, color_3d_medium);
            break;

        case Bevel::sunken:
            drawRectImpl(rect, color_3d_medium, color_3d_bright);
            break;

        case Bevel::input_field:
            drawRectImpl(rect, color_3d_medium, color_3d_bright);
            drawRectImpl(rect.shrink(1), color_3d_dark, color_background);
            break;

        case Bevel::button_default:
            drawRectImpl(rect, color_3d_bright, color_3d_dark);
            drawRectImpl(rect.shrink(1), color_background, color_3d_medium);
            break;

        case Bevel::button_active:
            drawRectImpl(rect, color_3d_black, color_3d_black);
            drawRectImpl(rect.shrink(1), color_3d_bright, color_3d_dark);
            drawRectImpl(rect.shrink(2), color_background, color_3d_medium);
            break;

        case Bevel::button_pressed:
            drawRectImpl(rect, color_3d_black, color_3d_black);
            drawRectImpl(rect.shrink(1), color_3d_medium, color_3d_medium);
            break;

        default:
            renderer.setColor(0xFF, 0x00, 0xFF, 0x80);
            renderer.drawRect(rect);
            break;
    }
}

void RenderContext::fillRect(const Rectangle & rect, Color color)
{
    SDL_Color c;
    switch (color) {
        case Color::highlight:
            c = color_highlight;
            break;
        case Color::background:
            c = color_background;
            break;
        case Color::input_field:
            c = color_input_field;
            break;
        case Color::checkered:
            c = color_checker;
            break;
    }
    renderer.setColor(c);
    renderer.fillRect(rect);
}

void RenderContext::drawIcon(const Rectangle & rect, SDL_Texture * texture, xstd::optional<Rectangle> clip_rect)
{
    if (clip_rect) {
        renderer.copy(texture, rect, *clip_rect);
    } else {
        renderer.copy(texture, rect);
    }
}

void RenderContext::drawHLine(int startX, int startY, int width, LineStyle style)
{
    renderer.setColor((style == LineStyle::edge) ? color_3d_bright : color_3d_medium);
    renderer.drawLine(startX, startY, startX + width - 1, startY);

    renderer.setColor((style == LineStyle::edge) ? color_3d_medium : color_3d_bright);
    renderer.drawLine(startX, startY + 1, startX + width - 1, startY + 1);
}

void RenderContext::drawVLine(int startX, int startY, int height, LineStyle style)
{
    renderer.setColor((style == LineStyle::edge) ? color_3d_bright : color_3d_medium);
    renderer.drawLine(startX, startY, startX, startY + height - 1);

    renderer.setColor((style == LineStyle::edge) ? color_3d_medium : color_3d_bright);
    renderer.drawLine(startX + 1, startY, startX + 1, startY + height - 1);
}

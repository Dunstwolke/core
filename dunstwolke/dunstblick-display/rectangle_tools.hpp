#ifndef RECTANGLE_TOOLS_HPP
#define RECTANGLE_TOOLS_HPP

#include <SDL.h>

static inline SDL_Rect intersect(SDL_Rect const & a, SDL_Rect const & b)
{
    auto const left = std::max(a.x, b.x);
    auto const top = std::max(a.y, b.y);

    auto const right = std::min(a.x + a.w, b.x + b.w);
    auto const bottom = std::min(a.y + a.h, b.y + b.h);

    if (right < left or bottom < top)
        return SDL_Rect{left, top, 0, 0};
    else
        return SDL_Rect{left, top, right - left, bottom - top};
}

static inline bool contains(SDL_Rect const & rect, int x, int y)
{
    return (x >= rect.x) and (y >= rect.y) and (x < rect.x + rect.w) and (y < rect.y + rect.h);
}

static inline bool contains(SDL_Rect const & rect, SDL_Point const & p)
{
    return contains(rect, p.x, p.y);
}

#endif // RECTANGLE_TOOLS_HPP

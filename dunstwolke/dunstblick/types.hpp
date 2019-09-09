#ifndef TYPES_HPP
#define TYPES_HPP

#include <cstdint>
#include <SDL.h>


struct SDL_Size { int w, h; };

/// RGB color structure
struct UIColor
{
    uint8_t r = 0x00;
    uint8_t g = 0x00;
    uint8_t b = 0x00;
    uint8_t a = 0xFF;

    operator SDL_Color () const {
        return { r, g, b, a };
    }
};

struct UIMargin
{
    int top, left, bottom, right;

    constexpr explicit UIMargin(int all)
        : top(all), left(all), bottom(all), right(all)
    {
    }

    constexpr explicit UIMargin(int horizontal, int vertical)
        : top(vertical), left(horizontal), bottom(vertical), right(horizontal)
    {
    }

    constexpr explicit UIMargin(int top, int left, int right, int bottom)
        : top(top), left(left), bottom(bottom), right(right)
    {
    }

    constexpr int totalHorizontal() const { return left + right; }
    constexpr int totalVertical() const { return top + bottom; }
};

#endif // TYPES_HPP

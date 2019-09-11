#ifndef TYPES_HPP
#define TYPES_HPP

#include <cstdint>
#include <SDL.h>
#include <variant>
#include <string>
#include <vector>
#include <xstd/unique_id>

#include "enums.hpp"

using UIResourceID = xstd::unique_id<struct UIResourceID_tag>;

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

    explicit UIMargin(int all);

    explicit UIMargin(int horizontal, int vertical);

    explicit UIMargin(int top, int left, int right, int bottom);

    constexpr int totalHorizontal() const { return left + right; }
    constexpr int totalVertical() const { return top + bottom; }

    bool operator== (UIMargin const & other) const {
        return (left == other.left)
           and (top == other.top)
           and (bottom == other.bottom)
           and (right == other.right)
        ;
    }
    bool operator!= (UIMargin const & other) const {
        return not (*this == other);
    }
};

struct UISizeAutoTag {};
struct UISizeExpandTag {};
//                             "auto",        "expand",        px,  percent
using UISizeDef = std::variant<UISizeAutoTag, UISizeExpandTag, int, float>;
static_assert(std::is_same_v<std::variant_alternative_t<0, UISizeDef>, UISizeAutoTag>);
static_assert(std::is_same_v<std::variant_alternative_t<1, UISizeDef>, UISizeExpandTag>);
static_assert(std::is_same_v<std::variant_alternative_t<2, UISizeDef>, int>);
static_assert(std::is_same_v<std::variant_alternative_t<3, UISizeDef>, float>);

using UISizeList = std::vector<UISizeDef>;

#include "types.variant.hpp"

#endif // TYPES_HPP

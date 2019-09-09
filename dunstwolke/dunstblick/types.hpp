#ifndef TYPES_HPP
#define TYPES_HPP

#include <cstdint>
#include <SDL.h>
#include <variant>
#include <string>
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
};

using UIValue = std::variant<
    std::monostate,
    int,
    float,
    std::string,
    uint8_t,
    UIMargin,
    UIColor,
    SDL_Size,
    SDL_Point,
    UIResourceID
>;

static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::invalid),     UIValue>, std::monostate>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::integer),     UIValue>, int>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::number),      UIValue>, float>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::string),      UIValue>, std::string>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::enumeration), UIValue>, uint8_t>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::margins),     UIValue>, UIMargin>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::color),       UIValue>, UIColor>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::size),        UIValue>, SDL_Size>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::point),       UIValue>, SDL_Point>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::resource),    UIValue>, UIResourceID>);


#endif // TYPES_HPP

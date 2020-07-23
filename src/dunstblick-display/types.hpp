#ifndef TYPES_HPP
#define TYPES_HPP

#include <cstdint>
#include <map>
#include <string>
#include <variant>
#include <vector>
#include <xstd/optional>
#include <xstd/unique_id>

#include <dunstblick.h>

#include "enums.hpp"

using UIResourceID = xstd::unique_id<struct UIResourceID_tag>;
using EventID = xstd::unique_id<struct CallbackID_tag>;
using WidgetName = xstd::unique_id<struct WidgetName_tag>;

struct UIPoint
{
    ssize_t x, y;

    UIPoint() = default;
    UIPoint(ssize_t x, ssize_t y) : x(x), y(y) {}
    UIPoint(dunstblick_Point pt) : x(pt.x), y(pt.y) {}

    operator dunstblick_Point() const
    {
        return dunstblick_Point{
            int32_t(x),
            int32_t(y),
        };
    }
};

struct UISize
{
    size_t w, h;

    UISize() = default;
    UISize(size_t w, size_t h) : w(w), h(h) {}
    UISize(dunstblick_Size size) : w(size.w), h(size.h) {}

    operator dunstblick_Size() const
    {
        return dunstblick_Size{
            uint32_t(w),
            uint32_t(h),
        };
    }
};

struct Rectangle
{
    ssize_t x, y;
    size_t w, h;

    constexpr Rectangle() : x(0), y(0), w(0), h(0) {}
    constexpr Rectangle(ssize_t _x, ssize_t _y, size_t _w, size_t _h) : x(_x), y(_y), w(_w), h(_h) {}

    static inline Rectangle intersect(Rectangle const & a, Rectangle const & b)
    {
        auto const left = std::max(a.x, b.x);
        auto const top = std::max(a.y, b.y);

        auto const right = std::min<ssize_t>(a.x + a.w, b.x + b.w);
        auto const bottom = std::min<ssize_t>(a.y + a.h, b.y + b.h);

        if (right < left or bottom < top)
            return Rectangle{left, top, 0, 0};
        else
            return Rectangle{left, top, size_t(right - left), size_t(bottom - top)};
    }

    inline bool contains(int px, int py) const
    {
        return (px >= this->x) and (py >= this->y) and (px < (this->x + this->w)) and (py < (this->y + this->h));
    }

    inline bool contains(UIPoint const & p) const
    {
        return contains(p.x, p.y);
    }

    bool empty() const
    {
        return (w * h) == 0;
    }

    Rectangle shrink(int n) const
    {
        return Rectangle{x + n, y + n, w - 2 * n, h - 2 * n};
    }
};

/// RGB color structure
struct UIColor : dunstblick_Color
{
    UIColor() = default;
    UIColor(dunstblick_Color c) : dunstblick_Color(c) {}

    bool operator==(UIColor c) const
    {
        return (r == c.r) and (g == c.g) and (b == c.b) and (a == c.a);
    }

    bool operator!=(UIColor c) const
    {
        return !(*this == c);
    }
};

struct UIMargin : dunstblick_Margins
{
    UIMargin(dunstblick_Margins m) : dunstblick_Margins(m) {}

    explicit UIMargin(int all);

    explicit UIMargin(int horizontal, int vertical);

    explicit UIMargin(int top, int left, int right, int bottom);

    constexpr int totalHorizontal() const
    {
        return left + right;
    }
    constexpr int totalVertical() const
    {
        return top + bottom;
    }

    bool operator==(UIMargin const & other) const
    {
        return (left == other.left) and (top == other.top) and (bottom == other.bottom) and (right == other.right);
    }
    bool operator!=(UIMargin const & other) const
    {
        return not(*this == other);
    }
};

struct UISizeAutoTag
{};
struct UISizeExpandTag
{};
//                             "auto",        "expand",        px,  percent
using UISizeDef = std::variant<UISizeAutoTag, UISizeExpandTag, int, float>;
static_assert(std::is_same_v<std::variant_alternative_t<0, UISizeDef>, UISizeAutoTag>);
static_assert(std::is_same_v<std::variant_alternative_t<1, UISizeDef>, UISizeExpandTag>);
static_assert(std::is_same_v<std::variant_alternative_t<2, UISizeDef>, int>);
static_assert(std::is_same_v<std::variant_alternative_t<3, UISizeDef>, float>);

inline bool operator==(UISizeExpandTag, UISizeExpandTag)
{
    return true;
}
inline bool operator!=(UISizeExpandTag, UISizeExpandTag)
{
    return false;
}

inline bool operator==(UISizeAutoTag, UISizeAutoTag)
{
    return true;
}
inline bool operator!=(UISizeAutoTag, UISizeAutoTag)
{
    return false;
}

inline bool operator==(UIPoint a, UIPoint b)
{
    return (a.x == b.x) and (a.y == b.y);
}
inline bool operator!=(UIPoint a, UIPoint b)
{
    return !(a == b);
}

inline bool operator==(UISize a, UISize b)
{
    return (a.w == b.w) and (a.h == b.h);
}
inline bool operator!=(UISize a, UISize b)
{
    return !(a == b);
}

using UISizeList = std::vector<UISizeDef>;

using ObjectID = xstd::unique_id<struct Object>;
using PropertyName = xstd::unique_id<struct ObjectProperty>;

struct Object;

struct IWidgetContext;

struct ObjectRef
{
    ObjectID id;

    explicit ObjectRef(std::nullptr_t);

    explicit ObjectRef(ObjectID id);

    explicit ObjectRef(Object const & obj);

    xstd::optional<Object &> try_resolve(IWidgetContext & session);
    xstd::optional<Object const &> try_resolve(IWidgetContext & session) const;

    bool is_resolvable(IWidgetContext & session) const;

    Object & resolve(IWidgetContext & session);
    Object const & resolve(IWidgetContext & session) const;

    bool operator==(ObjectRef const & o) const
    {
        return id == o.id;
    }

    bool operator!=(ObjectRef const & o) const
    {
        return id != o.id;
    }
};

using ObjectList = std::vector<ObjectRef>;

template <typename T>
constexpr UIType getUITypeFromType();

// include generated code
#include "types.variant.hpp"

struct ConversionOptions
{
    BooleanFormat booleanFormat = BooleanFormat::truefalse;
};

UIValue convertTo(UIValue const & value, UIType type, ConversionOptions const & options = {});

#endif // TYPES_HPP

#ifndef TYPES_HPP
#define TYPES_HPP

#ifndef DUNSTBLICK_COMPILER
#include <SDL.h>
#endif

#include <cstdint>
#include <map>
#include <string>
#include <variant>
#include <vector>
#include <xstd/flexref>
#include <xstd/optional>
#include <xstd/unique_id>

#include "enums.hpp"

using UIResourceID = xstd::unique_id<struct UIResourceID_tag>;
using EventID = xstd::unique_id<struct CallbackID_tag>;
using WidgetName = xstd::unique_id<struct WidgetName_tag>;

#ifdef DUNSTBLICK_SERVER
using UIPoint = SDL_Point;
#else
struct UIPoint
{
    int x, y;
};
#endif

struct UISize
{
    int w, h;
};

/// RGB color structure
struct UIColor
{
    uint8_t r = 0x00;
    uint8_t g = 0x00;
    uint8_t b = 0x00;
    uint8_t a = 0xFF;

#ifndef DUNSTBLICK_COMPILER
    operator SDL_Color() const
    {
        return {r, g, b, a};
    }
#endif

    bool operator==(UIColor c) const
    {
        return (r == c.r) and (g == c.g) and (b == c.b) and (a == c.a);
    }

    bool operator!=(UIColor c) const
    {
        return !(*this == c);
    }
};

struct UIMargin
{
    int top, left, bottom, right;

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

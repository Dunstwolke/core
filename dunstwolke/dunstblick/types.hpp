#ifndef TYPES_HPP
#define TYPES_HPP

#include <cstdint>
#include <SDL.h>
#include <variant>
#include <map>
#include <string>
#include <vector>
#include <xstd/unique_id>
#include <xstd/flexref>
#include <xstd/optional>

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

using ObjectID = xstd::unique_id<struct Object>;
using PropertyName = xstd::unique_id<struct ObjectProperty>;

struct ObjectProperty;
struct Object
{
	ObjectID id;
	std::map<PropertyName, ObjectProperty> properties;

	ObjectProperty & add(PropertyName, UIType type);

	template<typename T>
	ObjectProperty & add(PropertyName name, T const & value);

	xstd::optional<ObjectProperty&> get(PropertyName property);

	xstd::optional<ObjectProperty const &> get(PropertyName property) const;
};

using ObjectRef = xstd::flexref<Object>;

using ObjectList = std::vector<ObjectRef>;


template<typename T>
constexpr UIType getUITypeFromType();

// include generated code
#include "types.variant.hpp"

struct ObjectProperty
{
	UIType type;
	UIValue value;
};

struct ConversionOptions
{
	BooleanFormat booleanFormat = BooleanFormat::truefalse;
};

UIValue convertTo(UIValue const & value, UIType type, ConversionOptions const & options = { });


template<typename T>
ObjectProperty & Object::add(PropertyName name, const T & value)
{
	auto & prop = add(name, getUITypeFromType<T>());
	prop.value = value;
	return prop;
}

#endif // TYPES_HPP

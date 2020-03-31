#ifndef RESOURCES_HPP
#define RESOURCES_HPP

#include <cstdint>
#include <sdl2++/texture>
#include <variant>
#include <vector>
#include <xstd/optional>
#include <xstd/unique_id>

#include "inputstream.hpp"
#include "types.hpp"

#include "dunstblick.h"

enum class ResourceKind : uint8_t
{
    layout = DUNSTBLICK_RESOURCE_LAYOUT,
    bitmap = DUNSTBLICK_RESOURCE_BITMAP,
    drawing = DUNSTBLICK_RESOURCE_DRAWING,
};

struct BitmapResource
{
    sdl2::texture texture;

    UISize size;

    explicit BitmapResource(sdl2::texture && texture);
};

struct DrawingResource
{
    explicit DrawingResource();
};

struct LayoutResource
{
    std::vector<uint8_t> layout_data;

    explicit LayoutResource(uint8_t const * data, size_t length);

    InputStream get_stream() const;
};

using Resource = std::variant<LayoutResource, BitmapResource, DrawingResource>;

static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::layout), Resource>, LayoutResource>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::bitmap), Resource>, BitmapResource>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::drawing), Resource>, DrawingResource>);

inline bool is_bitmap(Resource const & r)
{
    return r.index() == size_t(ResourceKind::bitmap);
}

inline bool is_drawing(Resource const & r)
{
    return r.index() == size_t(ResourceKind::drawing);
}

inline bool is_layout(Resource const & r)
{
    return r.index() == size_t(ResourceKind::layout);
}

#endif // RESOURCES_HPP

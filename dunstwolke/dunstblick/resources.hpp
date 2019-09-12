#ifndef RESOURCES_HPP
#define RESOURCES_HPP

#include <vector>
#include <variant>
#include <cstdint>
#include <sdl2++/texture>

enum class ResourceKind : uint8_t
{
	layout  = 0,
	bitmap  = 1,
	drawing = 2,
};

struct BitmapResource
{
	sdl2::texture texture;

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
};

using Resource = std::variant<LayoutResource, BitmapResource, DrawingResource>;

static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::layout),  Resource>, LayoutResource>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::bitmap),  Resource>, BitmapResource>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::drawing), Resource>, DrawingResource>);

#endif // RESOURCES_HPP

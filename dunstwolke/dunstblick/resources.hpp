#ifndef RESOURCES_HPP
#define RESOURCES_HPP

#include <vector>
#include <variant>
#include <xstd/unique_id>
#include <cstdint>
#include <sdl2++/texture>
#include <xstd/optional>

#include "types.hpp"
#include "inputstream.hpp"

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

	InputStream get_stream() const;
};

using Resource = std::variant<LayoutResource, BitmapResource, DrawingResource>;

static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::layout),  Resource>, LayoutResource>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::bitmap),  Resource>, BitmapResource>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(ResourceKind::drawing), Resource>, DrawingResource>);

xstd::optional<Resource const &> find_resource(UIResourceID id);

inline bool is_bitmap(Resource const & r) {
	return r.index() == size_t(ResourceKind::bitmap);
}

inline bool is_drawing(Resource const & r) {
	return r.index() == size_t(ResourceKind::drawing);
}

inline bool is_layout(Resource const & r) {
	return r.index() == size_t(ResourceKind::layout);
}

template<typename T>
xstd::optional<T const &> get_resource(UIResourceID id)
{
	if(auto res = find_resource(id); res and std::holds_alternative<T>(*res))
		return std::get<T>(*res);
	else
		return xstd::nullopt;
}

void set_resource(UIResourceID id, Resource && resource);

#endif // RESOURCES_HPP

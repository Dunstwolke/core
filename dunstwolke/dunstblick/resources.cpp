#include "resources.hpp"

static std::map<UIResourceID, Resource> resources;

xstd::optional<Object &> get_object(UIResourceID id)
{
	if(auto it = resources.find(id); (it != resources.end()) and std::holds_alternative<Object>(it->second))
		return std::get<Object>(it->second);
	else
		return xstd::nullopt;
}

xstd::optional<Resource const &> find_resource(UIResourceID id)
{
	if(auto it = resources.find(id); it != resources.end())
		return it->second;
	else
		return xstd::nullopt;
}

void set_resource(UIResourceID id, Resource && resource)
{
	if(auto it = resources.find(id); it != resources.end())
		it->second = std::move(resource);
	else
		resources.emplace(id, std::move(resource));
}





BitmapResource::BitmapResource(sdl2::texture && _tex) :
  texture(std::move(_tex))
{

}

LayoutResource::LayoutResource(const uint8_t * data, size_t length) :
  layout_data(data, data + length)
{

}

InputStream LayoutResource::get_stream() const
{
	return InputStream { layout_data.data(), layout_data.size() };
}

DrawingResource::DrawingResource()
{

}

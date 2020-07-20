#include "resources.hpp"

BitmapResource::BitmapResource(Image * img, UISize size) : texture(img), size(size)
{
    assert(img != nullptr);
}

LayoutResource::LayoutResource(const uint8_t * data, size_t length) : layout_data(data, data + length)
{
    assert(data != nullptr);
}

InputStream LayoutResource::get_stream() const
{
    return InputStream{layout_data.data(), layout_data.size()};
}

DrawingResource::DrawingResource() {}

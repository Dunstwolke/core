#include "resources.hpp"

#include <cassert>

extern "C" void painting_image_destroy(Image * img);

BitmapResource::BitmapResource(Image * img, UISize size) : texture(img), size(size)
{
    assert(img != nullptr);
}

BitmapResource::BitmapResource(BitmapResource && other) : texture(other.texture), size(other.size)
{
    other.texture = nullptr;
}

BitmapResource::~BitmapResource()
{
    if (this->texture) {
        painting_image_destroy(this->texture);
    }
}

BitmapResource & BitmapResource::operator=(BitmapResource && other)
{
    this->texture = other.texture;
    this->size = other.size;
    other.texture = nullptr;
    return *this;
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

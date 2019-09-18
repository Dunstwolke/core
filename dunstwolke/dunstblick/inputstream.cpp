#include "inputstream.hpp"
#include <stdexcept>
#include <gsl/gsl>


InputStream::InputStream(const uint8_t *_data, size_t _length) :
    data(_data), length(_length), offset(0)
{

}

uint8_t InputStream::read_byte()
{
    if(offset >= length)
        throw std::out_of_range("stream is out of bytes");
    return data[offset++];
}

uint32_t InputStream::read_uint()
{
    uint32_t number = 0;

    uint8_t value;
    do {
        value = read_byte();
        number <<= 7;
        number |= value & 0x7F;
    } while((value & 0x80) != 0);

    return number;
}

float InputStream::read_float()
{
    uint8_t buf[4];
    buf[0] = read_byte();
    buf[1] = read_byte();
    buf[2] = read_byte();
    buf[3] = read_byte();
    return *reinterpret_cast<float const*>(buf);
}

std::string_view InputStream::read_string()
{
    auto const len = read_uint();
    if(offset + len >= length)
        throw std::out_of_range("stream is out of bytes!");
    std::string_view result(reinterpret_cast<char const *>(data + offset), len);
    offset += len;
	return result;
}

std::tuple<UIProperty, bool> InputStream::read_property_enum()
{
	auto value = read_byte();
	return std::make_tuple(UIProperty(value & 0x7F), (value & 0x80) != 0);
}

Object InputStream::read_object()
{
	ObjectID id = ObjectID(this->read_uint());
	Object obj { id };
	while(true)
	{
		auto const type = this->read_enum<UIType>();
		if(type == UIType::invalid)
			break;
		auto const name = PropertyName(this->read_uint());

		UIValue const value = this->read_value(type);

		obj.add(name, std::move(value));
	}
	return obj;
}

UIValue InputStream::read_value(UIType type)
{
	switch(type)
	{
		case UIType::invalid:
			throw std::runtime_error("Invalid property serialization: 'invalid' object discovered.");

		case UIType::objectlist:
		{
			ObjectList list;
			while(true)
			{
				ObjectID id(this->read_uint());
				if(id.is_null())
					break;
				list.push_back(ObjectRef { id });
			}
			return list;
		}

		case UIType::enumeration:
			return this->read_byte();

		case UIType::integer:
			return gsl::narrow<int>(this->read_uint());

		case UIType::resource:
			return UIResourceID(this->read_uint());

		case UIType::object: // objects are always references!
			return ObjectRef { ObjectID(this->read_uint()) };

		case UIType::number:
			return gsl::narrow<float>(this->read_float());

		case UIType::boolean:
			return (this->read_byte() != 0);

		case UIType::color:
		{
			UIColor color;
			color.r = this->read_byte();
			color.g = this->read_byte();
			color.b = this->read_byte();
			color.a = this->read_byte();
			return color;
		}

		case UIType::size:
		{
			SDL_Size size;
			size.w = gsl::narrow<int>(this->read_uint());
			size.h = gsl::narrow<int>(this->read_uint());
			return size;
		}

		case UIType::point:
		{
			SDL_Point pos;
			pos.x = gsl::narrow<int>(this->read_uint());
			pos.y = gsl::narrow<int>(this->read_uint());
			return pos;
		}

		case UIType::string:
			return std::string(this->read_string());

		case UIType::margins:
		{
			UIMargin margin(0);
			margin.left = gsl::narrow<int>(this->read_uint());
			margin.top = gsl::narrow<int>(this->read_uint());
			margin.right = gsl::narrow<int>(this->read_uint());
			margin.bottom = gsl::narrow<int>(this->read_uint());
			return margin;
		}

		case UIType::sizelist:
		{
			UISizeList list;

			auto len = this->read_uint();

			list.resize(len);
			for(size_t i = 0; i < list.size(); i += 4)
			{
				uint8_t value = this->read_byte();
				for(size_t j = 0; j < std::min(4UL, list.size() - i); j++)
				{
					switch((value >> (2 * j)) & 0x3)
					{
						case 0: list[i + j] = UISizeAutoTag { }; break;
						case 1: list[i + j] = UISizeExpandTag { }; break;
						case 2: list[i + j] = 0; break;
						case 3: list[i + j] = 1.0f; break;
					}
				}
			}

			for(size_t i = 0; i < list.size(); i++)
			{
				switch(list[i].index())
				{
					case 2: // pixels
						list[i] = int(this->read_uint());
						break;
					case 3: // percentage
						list[i] = this->read_float();
						break;
				}
			}

			return std::move(list);
		}

	}
	assert(false and "property type not in table yet!");
}

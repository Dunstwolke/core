#include "inputstream.hpp"
#include <gsl/gsl>
#include <stdexcept>

InputStream::InputStream(const uint8_t * _data, size_t _length) : DataReader(_data, _length) {}

std::tuple<UIProperty, bool> InputStream::read_property_enum()
{
    auto value = read_byte();
    return std::make_tuple(UIProperty(value & 0x7F), (value & 0x80) != 0);
}

Object InputStream::read_object()
{
    ObjectID id = ObjectID(this->read_uint());
    Object obj{id};
    while (true) {
        auto const type = this->read_enum<UIType>();
        if (type == UIType::invalid)
            break;
        auto const name = PropertyName(this->read_uint());

        UIValue const value = this->read_value(type);

        obj.add(name, std::move(value));
    }
    return obj;
}

UIValue InputStream::read_value(UIType type)
{
    switch (type) {
        case UIType::invalid:
            throw std::runtime_error("Invalid property serialization: 'invalid' object discovered.");

        case UIType::objectlist: {
            ObjectList list;
            while (true) {
                ObjectID id(this->read_uint());
                if (id.is_null())
                    break;
                list.push_back(ObjectRef{id});
            }
            return std::move(list);
        }

        case UIType::enumeration:
            return this->read_byte();

        case UIType::integer:
            return this->read_int();

        case UIType::resource:
            return UIResourceID(this->read_uint());

        case UIType::event:
            return EventID(this->read_uint());

        case UIType::object: // objects are always references!
            return ObjectRef{ObjectID(this->read_uint())};

        case UIType::number:
            return gsl::narrow<float>(this->read_float());

        case UIType::boolean:
            return (this->read_byte() != 0);

        case UIType::color: {
            UIColor color;
            color.r = this->read_byte();
            color.g = this->read_byte();
            color.b = this->read_byte();
            color.a = this->read_byte();
            return color;
        }

        case UIType::size: {
            UISize size;
            size.w = gsl::narrow<int>(this->read_uint());
            size.h = gsl::narrow<int>(this->read_uint());
            return size;
        }

        case UIType::point: {
            UIPoint pos;
            pos.x = this->read_int();
            pos.y = this->read_int();
            return pos;
        }

        case UIType::string:
            return std::string(this->read_string());

        case UIType::margins: {
            UIMargin margin(0);
            margin.left = this->read_int();
            margin.top = this->read_int();
            margin.right = this->read_int();
            margin.bottom = this->read_int();
            return margin;
        }

        case UIType::sizelist: {
            UISizeList list;

            auto len = this->read_uint();

            list.resize(len);
            for (size_t i = 0; i < list.size(); i += 4) {
                uint8_t value = this->read_byte();
                for (size_t j = 0; j < std::min(4UL, list.size() - i); j++) {
                    switch ((value >> (2 * j)) & 0x3) {
                        case 0:
                            list[i + j] = UISizeAutoTag{};
                            break;
                        case 1:
                            list[i + j] = UISizeExpandTag{};
                            break;
                        case 2:
                            list[i + j] = 0; // Set value to any "int"
                            break;
                        case 3:
                            list[i + j] = 1.0f; // Set value to any "float"
                            break;
                    }
                }
            }

            for (size_t i = 0; i < list.size(); i++) {
                switch (list[i].index()) {
                    case 2: // pixels
                        list[i] = int(this->read_uint());
                        break;
                    case 3: // percentage
                        list[i] = this->read_byte() / 100.0f;
                        break;
                }
            }

            return std::move(list);
        }
    }
    assert(false and "property type not in table yet!");
}

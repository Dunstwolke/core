#ifndef DUNSTBLICK_DATAWRITER_HPP
#define DUNSTBLICK_DATAWRITER_HPP

#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <gsl/gsl>
#include <vector>

#if defined(DUNSTBLICK_SERVER)
#include "types.hpp"
#endif

enum class ClientMessageType : uint8_t
{
    invalid = 0,
    uploadResource = 1,    // (rid, kind, data)
    addOrUpdateObject = 2, // (obj)
    removeObject = 3,      // (oid)
    setView = 4,           // (rid)
    setRoot = 5,           // (oid)
    setProperty = 6, // (oid, name, value) // "unsafe command", uses the serverside object type or fails of property
                     // does not exist
    clear = 7,       // (oid, name)
    insertRange = 8, // (oid, name, index, count, value …) // manipulate lists
    removeRange = 9, // (oid, name, index, count) // manipulate lists
    moveRange = 10,  // (oid, name, indexFrom, indexTo, count) // manipulate lists
};

enum class ServerMessageType : uint8_t
{
    invalid = 0,
    eventCallback = 1,   // (cid)
    propertyChanged = 2, // (oid, name, type, value)
};

struct CommandBuffer
{
    std::vector<std::byte> buffer;

    explicit CommandBuffer(ClientMessageType type) : buffer()
    {
        buffer.reserve(256);
        write_enum(uint8_t(type));
    }

    explicit CommandBuffer(ServerMessageType type) : buffer()
    {
        buffer.reserve(256);
        write_enum(uint8_t(type));
    }

    void write(void const * data, size_t len)
    {
        auto const offset = buffer.size();
        buffer.resize(offset + len);
        memcpy(buffer.data() + offset, data, len);
    }

    void write_enum(uint8_t value)
    {
        write(&value, 1);
    }

    void write_byte(uint8_t value)
    {
        write(&value, 1);
    }

    void write_varint(uint32_t value)
    {
        char buf[5];

        size_t maxidx = 4;
        for (size_t n = 0; n < 5; n++) {
            char & c = buf[4 - n];
            c = (value >> (7 * n)) & 0x7F;
            if (c != 0)
                maxidx = 4 - n;
            if (n > 0)
                c |= 0x80;
        }

        assert(maxidx < 5);
        write(buf + maxidx, 5 - maxidx);
    }

    void write_id(uint32_t id)
    {
        write_varint(id);
    }

    void write_number(float f)
    {
        write(&f, sizeof f);
    }

    void write_string(char const * text)
    {
        size_t len = strlen(text);
        write_varint(gsl::narrow<uint32_t>(len));
        write(text, len);
    }

    void write_string(char const * text, size_t length)
    {
        write_varint(gsl::narrow<uint32_t>(length));
        write(text, length);
    }

#ifdef DUNSTBLICK_LIBRARY
    void write_value(dunstblick_Value const & val, bool prefixType)
    {
        if (prefixType)
            write_enum(val.type);
        switch (val.type) {
            case DUNSTBLICK_TYPE_INTEGER: {
                write_varint(gsl::narrow<uint32_t>(val.integer));
                return;
            }

            case DUNSTBLICK_TYPE_NUMBER: {
                write_number(val.number);
                return;
            }

            case DUNSTBLICK_TYPE_STRING: {
                write_string(val.string);
                return;
            }

            case DUNSTBLICK_TYPE_ENUMERATION: {
                write_enum(val.enumeration);
                return;
            }

            case DUNSTBLICK_TYPE_MARGINS: {
                write_varint(gsl::narrow<uint32_t>(val.margins.left));
                write_varint(gsl::narrow<uint32_t>(val.margins.top));
                write_varint(gsl::narrow<uint32_t>(val.margins.right));
                write_varint(gsl::narrow<uint32_t>(val.margins.bottom));
                return;
            }

            case DUNSTBLICK_TYPE_COLOR: {
                write_byte(val.color.r);
                write_byte(val.color.g);
                write_byte(val.color.b);
                write_byte(val.color.a);
                return;
            }

            case DUNSTBLICK_TYPE_SIZE: {
                write_varint(gsl::narrow<uint32_t>(val.size.w));
                write_varint(gsl::narrow<uint32_t>(val.size.h));
                return;
            }

            case DUNSTBLICK_TYPE_POINT: {
                write_varint(gsl::narrow<uint32_t>(val.point.x));
                write_varint(gsl::narrow<uint32_t>(val.point.y));
                return;
            }

            case DUNSTBLICK_TYPE_RESOURCE: {
                write_varint(val.resource);
                return;
            }

            case DUNSTBLICK_TYPE_BOOLEAN: {
                write_byte(val.boolean ? 1 : 0);
                return;
            }

            case DUNSTBLICK_TYPE_OBJECT: {
                write_varint(val.resource);
                return;
            }

            case DUNSTBLICK_TYPE_OBJECTLIST: {
                assert(false and "not implemented yet");
                return;
            }
        }
        assert(false and "invalid value type: out of range!");
    }
#elif defined(DUNSTBLICK_SERVER)
    void write_value(UIValue const & val, bool prefixType)
    {
        if (prefixType)
            write_enum(gsl::narrow<uint8_t>(val.index()));
        switch (UIType(val.index())) {
            case UIType::integer: {
                write_varint(gsl::narrow<uint32_t>((std::get<int>(val))));
                return;
            }

            case UIType::number: {
                write_number(std::get<float>(val));
                return;
            }

            case UIType::enumeration: {
                write_enum(std::get<uint8_t>(val));
                return;
            }

            case UIType::string:
                write_string(std::get<std::string>(val).c_str());
                return;

            case UIType::boolean: {
                write_byte(std::get<bool>(val) ? 1 : 0);
                return;
            }

            case UIType::margins: {
                auto const & margins = std::get<UIMargin>(val);
                write_varint(gsl::narrow<uint32_t>(margins.left));
                write_varint(gsl::narrow<uint32_t>(margins.top));
                write_varint(gsl::narrow<uint32_t>(margins.right));
                write_varint(gsl::narrow<uint32_t>(margins.bottom));
                return;
            }

            case UIType::sizelist: {
                auto const & list = std::get<UISizeList>(val);

                // size of the list
                write_varint(gsl::narrow<uint32_t>(list.size()));

                // bitmask containing two bits per entry:
                // 00 = auto
                // 01 = expand
                // 10 = integer / pixels
                // 11 = number / percentage
                for (size_t i = 0; i < list.size(); i += 4) {
                    uint8_t value = 0;
                    for (size_t j = 0; j < std::min(4UL, list.size() - i); j++)
                        value |= (list[i + j].index() & 0x3) << (2 * j);
                    write_byte(value);
                }

                for (size_t i = 0; i < list.size(); i++) {
                    switch (list[i].index()) {
                        case 2: // pixels
                            write_varint(gsl::narrow<uint32_t>(std::get<int>(list[i])));
                            break;
                        case 3: // percentage
                            write_number(std::get<float>(list[i]));
                            break;
                    }
                }

                return;
            }

            case UIType::resource: {
                write_varint(gsl::narrow<uint32_t>(std::get<UIResourceID>(val).value));
                return;
            }

            case UIType::object: {
                write_varint(gsl::narrow<uint32_t>(std::get<ObjectRef>(val).id.value));
                return;
            }

            case UIType::callback: {
                write_varint(gsl::narrow<uint32_t>(std::get<CallbackID>(val).value));
                return;
            }

            case UIType::color: {
                auto const & col = std::get<UIColor>(val);
                write_byte(col.r);
                write_byte(col.g);
                write_byte(col.b);
                write_byte(col.a);
                return;
            }

            case UIType::size: {
                auto const & size = std::get<UISize>(val);
                write_varint(gsl::narrow<uint32_t>(size.w));
                write_varint(gsl::narrow<uint32_t>(size.h));
                return;
            }

            case UIType::point: {
                auto const & point = std::get<UIPoint>(val);
                write_varint(gsl::narrow<uint32_t>(point.x));
                write_varint(gsl::narrow<uint32_t>(point.y));
                return;
            }

            case UIType::objectlist: {
                auto const & list = std::get<ObjectList>(val);
                for (size_t i = 0; i < list.size(); i++) {
                    if (not list[i].id.is_null())
                        write_varint(gsl::narrow<uint32_t>(list[i].id.value));
                }
                write_varint(0);
                return;
            }

            case UIType::invalid:
                break;
        }
        assert(false and "not supported type!");
    }
#endif
};

#endif // DATAWRITER_HPP

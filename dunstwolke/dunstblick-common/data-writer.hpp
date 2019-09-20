#ifndef DUNSTBLICK_DATAWRITER_HPP
#define DUNSTBLICK_DATAWRITER_HPP

#include <cstdint>
#include <vector>
#include <cstddef>
#include <cassert>
#include <cstring>

enum class ClientMessageType : uint8_t
{
	invalid = 0,
	uploadResource = 1, // (rid, kind, data)
	addOrUpdateObject = 2, // (obj)
	removeObject = 3, // (oid)
	setView = 4, // (rid)
	setRoot = 5, // (oid)
	setProperty = 6, // (oid, name, value) // "unsafe command", uses the serverside object type or fails of property does not exist
	clear = 7, // (oid, name)
	insertRange = 8, // (oid, name, index, count, value …) // manipulate lists
	removeRange = 9, // (oid, name, index, count) // manipulate lists
	moveRange = 10, // (oid, name, indexFrom, indexTo, count) // manipulate lists
};

enum class ServerMessageType : uint8_t
{
	invalid = 0,
	eventCallback = 1, // (cid)
	propertyChanged = 2, // (oid, name, type, value)
};

struct CommandBuffer
{
	std::vector<std::byte> buffer;

	explicit CommandBuffer(ClientMessageType type) :
	    buffer()
	{
		buffer.reserve(256);
		write_enum(uint8_t(type));
	}

	explicit CommandBuffer(ServerMessageType type) :
	    buffer()
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
		for(size_t n = 0; n < 5; n++)
		{
			char & c = buf[4 - n];
			c = (value >> (7 * n)) & 0x7F;
			if(c != 0)
				maxidx = 4 - n;
			if(n > 0)
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
		write_varint(len);
		write(text, len);
	}

	void write_string(char const * text, size_t length)
	{
		write_varint(length);
		write(text, length);
	}

#ifdef DUNSTBLICK_LIBRARY
	void write_value(dunstblick_Value const & val, bool prefixType)
	{
		if(prefixType)
			write_enum(val.type);
		switch(val.type)
		{
			case DUNSTBLICK_TYPE_INTEGER:
			{
				write_varint(val.integer);
				break;
			}

			case DUNSTBLICK_TYPE_NUMBER:
			{
				write_number(val.number);
				break;
			}

			case DUNSTBLICK_TYPE_STRING:
			{
				write_string(val.string);
				break;
			}

			case DUNSTBLICK_TYPE_ENUMERATION:
			{
				write_enum(val.enumeration);
				break;
			}

			case DUNSTBLICK_TYPE_MARGINS:
			{
				write_varint(val.margins.left);
				write_varint(val.margins.top);
				write_varint(val.margins.right);
				write_varint(val.margins.bottom);
				break;
			}

			case DUNSTBLICK_TYPE_COLOR:
			{
				write_byte(val.color.r);
				write_byte(val.color.g);
				write_byte(val.color.b);
				write_byte(val.color.a);
				break;
			}

			case DUNSTBLICK_TYPE_SIZE:
			{
				write_varint(val.size.w);
				write_varint(val.size.h);
				break;
			}

			case DUNSTBLICK_TYPE_POINT:
			{
				write_varint(val.point.x);
				write_varint(val.point.y);
				break;
			}

			case DUNSTBLICK_TYPE_RESOURCE:
			{
				write_varint(val.resource);
				break;
			}

			case DUNSTBLICK_TYPE_BOOLEAN:
			{
				write_byte(val.boolean ? 1 : 0);
				break;
			}

			case DUNSTBLICK_TYPE_OBJECT:
			{
				write_varint(val.resource);
				break;
			}

			case DUNSTBLICK_TYPE_OBJECTLIST:
			{
				assert(false and "not implemented yet");
				break;
			}

			default:
				assert(false and "invalid value type: out of range!");
		}
	}
#endif
};

#endif // DATAWRITER_HPP

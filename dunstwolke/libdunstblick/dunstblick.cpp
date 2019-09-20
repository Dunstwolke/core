#include "dunstblick.h"

#include <xnet/socket>
#include <xnet/socket_stream>
#include <xnet/dns>

#include <cassert>
#include <cstring>
#include <cstdarg>

namespace
{
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

	struct CommandBuffer
	{
		std::vector<std::byte> buffer;

		explicit CommandBuffer(ClientMessageType type) :
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
	};
}

struct dunstblick_Connection
{
	xnet::socket sock;

	dunstblick_Connection(xnet::socket && _sock) :
	    sock(std::move(_sock))
	{

	}

	// copying a connection is not logical,
	dunstblick_Connection(dunstblick_Connection const &) = delete;

	// but moving a connection is not allowed due to
	// pointer handle semantics on C side.
	dunstblick_Connection(dunstblick_Connection &&) = delete;

	~dunstblick_Connection()
	{

	}

	bool send(CommandBuffer const & buffer)
	{
		try
		{
			uint32_t length = buffer.buffer.size();

			xnet::socket_ostream stream { sock };

			stream.write<uint32_t>(length);
			stream.write(buffer.buffer.data(), length);
		}
		catch(...)
		{
			return false;
		}

		return true;
	}
};

struct dunstblick_Object
{
	dunstblick_Connection * const connection;

	CommandBuffer commandbuffer;

	dunstblick_Object(dunstblick_Connection * con) :
	    connection(con),
	    commandbuffer(ClientMessageType::addOrUpdateObject)
	{
	}

	dunstblick_Object(dunstblick_Object const &) = delete;
	dunstblick_Object(dunstblick_Object &&) = delete;

	~dunstblick_Object()
	{

	}
};

#include <stdio.h>

dunstblick_Connection * dunstblick_Open(const char * host, int portNumber)
{
	std::optional<xnet::socket> sock;

	for (auto const & entry : xnet::dns::resolve(host, std::to_string(portNumber), SOCK_STREAM))
	{
		sock.emplace(entry.family, entry.socket_type, entry.protocol);
		if(sock->connect(entry.address))
			break;
		else
			sock.reset();
	}

	if(not sock)
		return nullptr;

	return new dunstblick_Connection(std::move(*sock));
}

void dunstblick_Close(dunstblick_Connection * con)
{
	delete con;
}

dunstblick_Error dunstblick_UploadResource(dunstblick_Connection * con, dunstblick_ResourceID rid, dunstblick_ResourceKind kind, const void * data, size_t length)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::uploadResource };
	buffer.write_id(rid);
	buffer.write_enum(kind);
	buffer.write(data, length);

	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;

	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Object * dunstblick_AddOrUpdateObject(dunstblick_Connection * con, dunstblick_ObjectID id)
{
	if(con == nullptr)
		return nullptr;
	if(id == 0)
		return nullptr;

	auto * obj = new dunstblick_Object(con);
	obj->commandbuffer.write_id(id);
	return obj;
}

dunstblick_Error dunstblick_RemoveObject(dunstblick_Connection * con, dunstblick_ObjectID oid)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(oid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::removeObject };
	buffer.write_id(oid);
	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;

	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_SetView(dunstblick_Connection * con, dunstblick_ResourceID rid)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(rid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::setView };
	buffer.write_id(rid);
	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;

	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_SetRoot(dunstblick_Connection * con, dunstblick_ObjectID oid)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(oid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::setRoot };
	buffer.write_id(oid);

	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;
	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_SetProperty(dunstblick_Connection * con, dunstblick_ObjectID oid, dunstblick_PropertyName name, const dunstblick_Value * value)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(oid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(value == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(value->type == 0)
		return DUNSTBLICK_ERROR_INVALID_TYPE;

	CommandBuffer buffer { ClientMessageType::setProperty };
	buffer.write_id(oid);
	buffer.write_id(name);
	buffer.write_value(*value, true);

	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;
	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_Clear(dunstblick_Connection * con, dunstblick_ObjectID oid, dunstblick_PropertyName name)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(oid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(name == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::clear };
	buffer.write_id(oid);
	buffer.write_id(name);

	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;
	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_InsertRange(dunstblick_Connection * con, dunstblick_ObjectID oid, dunstblick_PropertyName name, size_t index, size_t count, const dunstblick_ObjectID * values)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(oid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(name == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(values == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::insertRange };
	buffer.write_id(oid);
	buffer.write_id(name);
	buffer.write_varint(index);
	buffer.write_varint(count);
	for(size_t i = 0; i < count; i++)
		buffer.write_id(values[i]);

	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;
	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_RemoveRange(dunstblick_Connection * con, dunstblick_ObjectID oid, dunstblick_PropertyName name, size_t index, size_t count)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(oid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(name == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::removeRange };
	buffer.write_id(oid);
	buffer.write_id(name);
	buffer.write_varint(index);
	buffer.write_varint(count);

	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;
	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_MoveRange(dunstblick_Connection * con, dunstblick_ObjectID oid, dunstblick_PropertyName name, size_t indexFrom, size_t indexTo, size_t count)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(oid == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(name == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	CommandBuffer buffer { ClientMessageType::moveRange };
	buffer.write_id(oid);
	buffer.write_id(name);
	buffer.write_varint(indexFrom);
	buffer.write_varint(indexTo);
	buffer.write_varint(count);

	if(not con->send(buffer))
		return DUNSTBLICK_ERROR_NETWORK;
	return DUNSTBLICK_ERROR_NONE;
}



dunstblick_Error dunstblick_SetObjectProperty(dunstblick_Object * obj, dunstblick_PropertyName name, dunstblick_Value const * value)
{
	if(obj == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(name == 0)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(value == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	if(value->type == 0)
		return DUNSTBLICK_ERROR_INVALID_TYPE;

	obj->commandbuffer.write_enum(value->type);
	obj->commandbuffer.write_id(name);
	obj->commandbuffer.write_value(*value, false);

	return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_CloseObject(dunstblick_Object * obj)
{
	if(not obj)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	obj->commandbuffer.write_enum(0);

	bool sendOk = obj->connection->send(obj->commandbuffer);

	delete obj;

	if(not sendOk)
		return DUNSTBLICK_ERROR_NETWORK;
	return DUNSTBLICK_ERROR_NONE;
}

void dunstblick_CancelObject(dunstblick_Object * obj)
{
	if(obj)
		delete obj;
}

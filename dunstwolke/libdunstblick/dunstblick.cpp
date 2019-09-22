#include "dunstblick.h"

#include <xnet/socket>
#include <xnet/socket_stream>
#include <xnet/dns>
#include <xstd/locked_value>
#include <xcept>

#include <cassert>
#include <cstring>
#include <cstdarg>
#include <thread>
#include <mutex>

#include <queue>

#include "../dunstblick-common/data-writer.hpp"
#include "../dunstblick-common/data-reader.hpp"

static void receive_data(dunstblick_Connection * con);

using InputPacket = std::vector<std::byte>;

struct dunstblick_Connection
{
	xnet::socket sock;
	xstd::locked_value<std::queue<InputPacket>> packets;
	std::thread receiver_thread;
	std::atomic_flag shutdown_request;

	dunstblick_Connection(xnet::socket && _sock) :
	    sock(std::move(_sock)),
	    packets(),
	    receiver_thread(receive_data, this)
	{

	}

	// copying a connection is not logical,
	dunstblick_Connection(dunstblick_Connection const &) = delete;

	// but moving a connection is not allowed due to
	// pointer handle semantics on C side.
	dunstblick_Connection(dunstblick_Connection &&) = delete;

	~dunstblick_Connection()
	{
		 shutdown_request.clear();
		 sock.shutdown();
		 receiver_thread.join();
	}

	bool send(CommandBuffer const & buffer)
	{
		try
		{
			uint32_t length = gsl::narrow<uint32_t>(buffer.buffer.size());

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

static void receive_data(dunstblick_Connection * con)
{
	assert(con != nullptr);
	con->shutdown_request.test_and_set();
	try
	{
		auto stream = xnet::socket_istream { con->sock };

		bool connected = true;
		while(con->shutdown_request.test_and_set())
		{
			auto length = stream.read<uint32_t>();
			if(connected > 0)
			{
				InputPacket p(length);
				stream.read(p.data(), p.size());

				con->packets.obtain()->emplace(std::move(p));

			}
			else
			{
				connected = false;
			}
		}
	}
	catch(xcept::end_of_stream const &)
	{
		// client closed connection...
	}
}

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


dunstblick_Error dunstblick_PumpEvents(dunstblick_Connection * con, dunstblick_EventHandler const * eha, void * context)
{
	if(con == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;
	if(eha == nullptr)
		return DUNSTBLICK_ERROR_INVALID_ARG;

	auto list = con->packets.obtain();
	while(list->size() > 0)
	{
		auto packet = std::move(list->front());
		list->pop();

		DataReader reader { packet.data(), packet.size() };

		auto const msgtype = ServerMessageType(reader.read_byte());

		switch(msgtype)
		{
			case ServerMessageType::eventCallback:
			{
				auto const id = reader.read_uint();
				if(eha->onCallback != nullptr)
					eha->onCallback(id, context);
				break;
			}
			case ServerMessageType::propertyChanged:
			{
				auto const obj_id = reader.read_uint();
				auto const property = reader.read_uint();
				auto const type = dunstblick_Type(reader.read_byte());

				dunstblick_Value value = reader.read_value(type);

				if(eha->onPropertyChanged != nullptr)
					eha->onPropertyChanged(obj_id, property, &value);

				break;
			}
			default:
				// log some message?
				break;
		}
	}

	return  DUNSTBLICK_ERROR_NONE;
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

dunstblick_Object * dunstblick_BeginChangeObject(dunstblick_Connection * con, dunstblick_ObjectID id)
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
	buffer.write_varint(gsl::narrow<uint32_t>(index));
	buffer.write_varint(gsl::narrow<uint32_t>(count));
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
	buffer.write_varint(gsl::narrow<uint32_t>(index));
	buffer.write_varint(gsl::narrow<uint32_t>(count));

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
	buffer.write_varint(gsl::narrow<uint32_t>(indexFrom));
	buffer.write_varint(gsl::narrow<uint32_t>(indexTo));
	buffer.write_varint(gsl::narrow<uint32_t>(count));

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

dunstblick_Error dunstblick_CommitObject(dunstblick_Object * obj)
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

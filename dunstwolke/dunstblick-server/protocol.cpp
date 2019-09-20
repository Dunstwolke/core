#include "protocol.hpp"
#include "inputstream.hpp"
#include "api.hpp"

#include <cassert>
#include <xlog>

static ProtocolAdapter adapter;

static inline void msg_send(std::uint8_t const * payload, size_t len)
{
	assert(adapter.send != nullptr);
	adapter.send(payload, len, adapter.context);
}

static inline std::optional<Packet> msg_receive()
{
	assert(adapter.receive != nullptr);
	return adapter.receive(adapter.context);
}

void set_protocol_adapter(const ProtocolAdapter & ada)
{
	adapter = ada;
}

static void parse_and_exec_msg(Packet const & msg)
{
	InputStream stream(msg.data(), msg.size());

	auto const msgType = ClientMessageType(stream.read_byte());
	switch(msgType)
	{
		case ClientMessageType::uploadResource: // (rid, kind, data)
		{
			auto resource = stream.read_id<UIResourceID>();
			auto kind = stream.read_enum<ResourceKind>();

			auto const [ data, len ] = stream.read_to_end();

			API::uploadResource(resource, kind, data, len);
			break;
		}

		case ClientMessageType::addOrUpdateObject: // (obj)
		{
			auto obj = stream.read_object();
			API::addOrUpdateObject(std::move(obj));
			break;
		}

		case ClientMessageType::removeObject: // (oid)
		{
			auto const oid = stream.read_id<ObjectID>();
			API::removeObject(oid);
			break;
		}

		case ClientMessageType::setView: // (rid)
		{
			auto const rid = stream.read_id<UIResourceID>();
			API::setView(rid);
			break;
		}

		case ClientMessageType::setRoot: // (oid)
		{
			auto const oid = stream.read_id<ObjectID>();
			API::setRoot(oid);
			break;
		}

		case ClientMessageType::setProperty: // (oid, name, value)
		{
			auto const oid = stream.read_id<ObjectID>();
			auto const propName = stream.read_id<PropertyName>();
			auto const type = stream.read_enum<UIType>();
			auto const value = stream.read_value(type);

			API::setProperty(oid, propName, value);
			break;
		}

		case ClientMessageType::clear: // (oid, name)
		{
			auto const oid = stream.read_id<ObjectID>();
			auto const propName = stream.read_id<PropertyName>();
			API::clear(oid, propName);
			break;
		}

		case ClientMessageType::insertRange: // (oid, name, index, count, oids …) // manipulate lists
		{
			auto const oid = stream.read_id<ObjectID>();
			auto const propName = stream.read_id<PropertyName>();
			auto const index = stream.read_uint();
			auto const count = stream.read_uint();
			std::vector<ObjectRef> refs;
			refs.reserve(count);
			for(size_t i = 0; i < count; i++)
				refs.emplace_back(stream.read_id<ObjectID>());
			API::insertRange(oid, propName, index, count, refs.data());
			break;
		}

		case ClientMessageType::removeRange: // (oid, name, index, count) // manipulate lists
		{
			auto const oid = stream.read_id<ObjectID>();
			auto const propName = stream.read_id<PropertyName>();
			auto const index = stream.read_uint();
			auto const count = stream.read_uint();
			API::removeRange(oid, propName, index, count);
			break;
		}

		case ClientMessageType::moveRange: // (oid, name, indexFrom, indexTo, count) // manipulate lists
		{
			auto const oid = stream.read_id<ObjectID>();
			auto const propName = stream.read_id<PropertyName>();
			auto const indexFrom = stream.read_uint();
			auto const indexTo = stream.read_uint();
			auto const count = stream.read_uint();
			API::moveRange(oid, propName, indexFrom, indexTo, count);
			break;
		}

		default:
			xlog::log(xlog::error) << "received message of unknown type: " << std::to_string(uint8_t(msgType));
			break;
	}
}

void do_communication()
{
	std::optional<Packet> msg;
	while((msg = msg_receive()))
	{
		parse_and_exec_msg(*msg);
	}
}

void send_message(CommandBuffer const & buffer)
{
	msg_send(reinterpret_cast<uint8_t const *>(buffer.buffer.data()), buffer.buffer.size());
}

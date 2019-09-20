#ifndef PROTOCOL_HPP
#define PROTOCOL_HPP

#include <vector>
#include <optional>

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

using Packet = std::vector<std::uint8_t>;

struct ProtocolAdapter
{
	void * context;

	/// sends a packet nonblockingly
	void (*send)(std::uint8_t const * payload, size_t len, void * context);

	/// nonblockingly checks for a received packet
	std::optional<Packet> (*receive)(void * context);

	template<typename T>
	static ProtocolAdapter createFrom(T & implementor)
	{
		ProtocolAdapter adapter;
		adapter.send = [](std::uint8_t const * payload, size_t len, void * _context)
		{
			static_cast<T*>(_context)->send(payload, len);
		};
		adapter.receive = [](void * _context) -> std::optional<Packet>
		{
			return static_cast<T*>(_context)->receive();
		};
		adapter.context = &implementor;
		return adapter;
	}
};

void set_protocol_adapter(ProtocolAdapter const & adapter);

void do_communication();

#endif // PROTOCOL_HPP

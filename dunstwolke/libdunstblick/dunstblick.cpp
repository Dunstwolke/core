#include "dunstblick.h"
#include "dunstblick-internal.hpp"

#include <xnet/socket>
#include <xnet/socket_stream>
#include <xnet/dns>
#include <xstd/locked_value>
#include <xcept>

#include <arpa/inet.h>

#include <cassert>
#include <cstring>
#include <cstdarg>
#include <thread>
#include <mutex>

#include <queue>

#include "../dunstblick-common/data-writer.hpp"
#include "../dunstblick-common/data-reader.hpp"


// playing around with C++ operator overloading:
struct check
{
    char const * msg;
    check(char const * _msg) : msg(_msg) { }

    void operator=(bool b) const {
        if(b)
            return;
        fprintf(stderr, "%s\n", msg);
        fflush(stderr);
    }
};

struct dunstblick_Provider
{
    xnet::socket multicast_sock;
    xnet::socket tcp_sock;
    std::string discovery_name;
    std::thread worker_thread;
    std::atomic_flag shutdown_request;

    dunstblick_Provider(char const * discoveryName);

    dunstblick_Provider(dunstblick_Provider const &) = delete;
    dunstblick_Provider(dunstblick_Provider &&) = delete;

    ~dunstblick_Provider();
};

static void provider_mainloop(dunstblick_Provider * provider);

dunstblick_Provider::dunstblick_Provider(char const * discoveryName) :
    multicast_sock(AF_INET, SOCK_DGRAM, 0),
    tcp_sock(AF_INET, SOCK_STREAM, 0),
    discovery_name(discoveryName),
    worker_thread(),
    shutdown_request(true)
{
    check("tcp bind") = tcp_sock.bind(xnet::parse_ipv4("0.0.0.0", 0));

    check("tcp listen") = tcp_sock.listen();

    check("udp reuse") = multicast_sock.set_option<int>(SOL_SOCKET, SO_REUSEADDR, 1);
    check("udp broadcast") = multicast_sock.set_option<int>(SOL_SOCKET, SO_BROADCAST, 1);

    check("udp bind") = multicast_sock.bind(xnet::parse_ipv4("0.0.0.0", DUNSTBLICK_DEFAULT_PORT));

    ip_mreq mcast_request;
    mcast_request.imr_interface.s_addr = INADDR_ANY;
    mcast_request.imr_multiaddr.s_addr = inet_addr(DUNSTBLICK_MULTICAST_GROUP);
    check("udp join") = multicast_sock.set_option<ip_mreq>(SOL_SOCKET, IP_ADD_MEMBERSHIP, mcast_request);

    check("udp loop") = multicast_sock.set_option<int>(SOL_SOCKET, IP_MULTICAST_LOOP, 1);

    this->worker_thread = std::thread(provider_mainloop, this);
}

dunstblick_Provider::~dunstblick_Provider()
{
    shutdown_request.clear();

    worker_thread.join();

    ip_mreq mcast_request;
    mcast_request.imr_interface.s_addr = INADDR_ANY;
    mcast_request.imr_multiaddr.s_addr = inet_addr(DUNSTBLICK_MULTICAST_GROUP);
    check("udp drop") = multicast_sock.set_option<ip_mreq>(SOL_SOCKET, IP_DROP_MEMBERSHIP, mcast_request);
}

struct FDSet
{
    fd_set set;
    int max_fd;

    FDSet() {
        FD_ZERO(&set);
        max_fd = 0;
    }

    void add(int fd) {
        max_fd = std::max(max_fd, fd);
        FD_SET(fd, &set);
    }

    bool check(int fd) const {
        return FD_ISSET(fd, &set);
    }
};

static void provider_mainloop(dunstblick_Provider * provider)
{
    auto const tcp_listener_ep = provider->tcp_sock.get_local_endpoint();

    fprintf(stderr, "listening on %s\n", xnet::to_string(tcp_listener_ep).c_str());

    while(provider->shutdown_request.test_and_set())
    {
        FDSet read_fds;
        read_fds.add(provider->multicast_sock.handle);
        read_fds.add(provider->tcp_sock.handle);

        timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 10000;

        int result = select(read_fds.max_fd + 1, &read_fds.set, nullptr, nullptr, &timeout);
        if(result < 0) {
            perror("failed to select:");
        }

        if(read_fds.check(provider->multicast_sock.handle))
        {
            fflush(stdout);

            UdpBaseMessage message;

            auto const [ssize, sender] = provider->multicast_sock.read_from(&message, sizeof message);
            if(ssize < 0) {
                perror("read udp failed");
            }
            else {
                size_t size = size_t(ssize);
                if(size < sizeof(message.header)) {
                    fprintf(stderr, "udp message too small…\n");
                }
                else {
                    if(message.header.magic == UdpHeader::real_magic)
                    {
                        switch(message.header.type)
                        {
                        case UDP_DISCOVER: {
                            if(size >= sizeof(message.discover)) {

                                UdpDiscoverResponse response;
                                response.header = UdpHeader::create(UDP_RESPOND_DISCOVER);
                                response.tcp_port = uint16_t(tcp_listener_ep.port());
                                response.length = provider->discovery_name.size();

                                strncpy(
                                    response.name.data(),
                                    provider->discovery_name.c_str(),
                                    response.name.size()
                                );

                                fprintf(stderr, "response to %s\n", xnet::to_string(sender).c_str());
                                fflush(stderr);

                                ssize_t const sendlen = provider->multicast_sock.write_to(sender, &response, sizeof response);
                                if(sendlen < 0) {
                                    perror("failed to send discovery response");
                                }
                                else if(sendlen < sizeof(response)) {
                                    fprintf(stderr, "expected to send %lu bytes, got %ld\n", sizeof(response), sendlen);
                                }
                            }
                            else {
                                fprintf(stderr, "expected %lu bytes, got %ld\n", sizeof(message.discover), size);
                            }
                            break;
                        }
                        case UDP_RESPOND_DISCOVER: {
                            if(size >= sizeof(message.discover_response)) {
                                fprintf(stderr, "got udp response\n");
                            }
                            else {
                                fprintf(stderr, "expected %lu bytes, got %ld\n", sizeof(message.discover_response), size);
                            }
                            break;
                        }
                        default:
                            fprintf(stderr, "invalid packet type: %u\n", message.header.type);
                        }
                    }
                    else
                    {
                        fprintf(
                            stderr,
                            "Invalid packet magic: %02X%02X%02X%02X\n",
                            message.header.magic[0],
                            message.header.magic[1],
                            message.header.magic[2],
                            message.header.magic[3]
                        );
                    }
                }
            }
        }
        if(read_fds.check(provider->tcp_sock.handle))
        {
            auto [ socket, endpoint ] = provider->tcp_sock.accept();

            fprintf(stderr, "client connected from %s\n", to_string(endpoint).c_str());
        }
    }
}


dunstblick_Provider *dunstblick_OpenProvider(const char *discoveryName)
{
    if(discoveryName == nullptr)
        return nullptr;
    if(strlen(discoveryName) > DUNSTBLICK_MAX_APP_NAME_LENGTH)
        return nullptr;
    try {
        return new dunstblick_Provider(discoveryName);
    }
    catch (std::bad_alloc) {
        return nullptr;
    }
}

void dunstblick_CloseProvider(dunstblick_Provider *provider)
{
    if(provider != nullptr)
        delete provider;
}

/*

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
    if(host == nullptr)
        return nullptr;

    if(portNumber <= 0 or portNumber >= 65536)
        return nullptr;

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

*/

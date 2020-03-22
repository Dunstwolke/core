#include "dunstblick.h"

#include <arpa/inet.h>

#include <cassert>
#include <cstdarg>
#include <cstring>
#include <list>
#include <map>
#include <mutex>
#include <queue>
#include <thread>
#include <xcept>
#include <xnet/dns>
#include <xnet/socket>
#include <xnet/socket_stream>
#include <xstd/locked_value>

#include "dunstblick-internal.hpp"

using mutex_guard = std::lock_guard<std::mutex>;

#include "../dunstblick-common/data-reader.hpp"
#include "../dunstblick-common/data-writer.hpp"

// playing around with C++ operator overloading:
struct check
{
    char const * msg;
    check(char const * _msg) : msg(_msg) {}

    void operator=(bool b) const
    {
        if (b)
            return;
        fprintf(stderr, "%s\n", msg);
        fflush(stderr);
    }
};

template <size_t N>
static std::string extract_string(std::array<char, N> const & item)
{
    size_t length = 0;
    while (length < item.size()) {
        if (item[length] == 0)
            break;
        length += 1;
    }
    return std::string(item.data(), length);
}

template <typename F>
struct Callback
{
    F function;
    void * user_data;

    Callback() : function(nullptr), user_data(nullptr) {}
    Callback(F item, void * ud) : function(item), user_data(ud) {}

    template <typename... Args>
    void invoke(Args &&... args)
    {
        if (function != nullptr) {
            function(std::forward<Args>(args)..., user_data);
        } else {
            fprintf(stderr, "callback does not exist!\n");
        }
    }
};

struct ConnectionHeader
{
    std::string clientName;
    std::string password;
    dunstblick_ClientCapabilities capabilities;
};

using Md5Hash = std::array<uint8_t, 16>;

extern "C" void compute_hash(void const * data, size_t length, void * out);

static Md5Hash compute_hash(void const * data, size_t length)
{
    Md5Hash hash;
    compute_hash(data, length, hash.data());
    return hash;
}

struct StoredResource
{
    dunstblick_ResourceID id;
    dunstblick_ResourceKind type;
    std::vector<uint8_t> data;
    Md5Hash hash;

    void update_hash()
    {
        hash = compute_hash(data.data(), data.size());
    }
};

struct dunstblick_Connection
{
    enum State
    {
        READ_HEADER,
        READ_REQUIRED_RESOURCE_HEADER,
        READ_REQUIRED_RESOURCES,
        SEND_RESOURCES,
        READY,
    };

    std::mutex mutex;
    xnet::socket sock;
    xnet::endpoint remote;
    State state;

    bool is_initialized;
    std::optional<dunstblick_DisconnectReason> disconnect_reason;

    ConnectionHeader header;
    dunstblick_Size screenResolution;

    std::vector<uint8_t> receive_buffer;
    dunstblick_Provider * provider;

    size_t required_resource_count;                        ///< total number of resources required by the display client
    std::vector<dunstblick_ResourceID> required_resources; ///< ids of the required resources
    size_t resource_send_index;                            ///< currently transmitted resource
    size_t resource_send_offset;                           ///< current byte offset in the resource

    dunstblick_Connection(dunstblick_Provider * provider, xnet::socket && sock, xnet::endpoint const & ep);
    dunstblick_Connection(dunstblick_Connection const &) = delete;
    dunstblick_Connection(dunstblick_Connection &&) = delete;
    ~dunstblick_Connection();

    void drop(dunstblick_DisconnectReason reason);

    //! Shoves data from the display server into the connection.
    void push_data(void const * blob, size_t length);

    //! Is called whenever the socket is ready to send
    //! data and we're not yet in "READY" state
    void send_data();
};

struct dunstblick_Provider
{
    std::mutex mutex;
    xnet::socket multicast_sock;
    xnet::socket tcp_sock;
    std::string discovery_name;
    std::thread worker_thread;
    std::atomic_flag shutdown_request;

    std::mutex resource_lock;
    std::map<dunstblick_ResourceID, StoredResource> resources;

    std::list<dunstblick_Connection> pending_connections;
    std::list<dunstblick_Connection> established_connections;

    Callback<dunstblick_ConnectedCallback> onConnected;
    Callback<dunstblick_DisconnectedCallback> onDisconnected;

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

    if (not tcp_sock.set_option<int>(SOL_SOCKET, SO_REUSEADDR, 1))
        throw xcept::io_error("Failed to set REUSEADDR on tcp listener.");

    // TODO: Replace fixed port with 0 for dynamic dispatch
    if (not tcp_sock.bind(xnet::parse_ipv4("0.0.0.0", 39101)))
        throw xcept::io_error("Failed to bind TCP socket.");

    if (not tcp_sock.listen())
        throw xcept::io_error("Failed to listen on TCP socket.");

    if (not multicast_sock.set_option<int>(SOL_SOCKET, SO_REUSEADDR, 1))
        throw xcept::io_error("Failed to set REUSEADDR on multicast socket.");

    // multicast_sock.set_option<int>(SOL_SOCKET, SO_BROADCAST, 1);

    if (not multicast_sock.bind(xnet::parse_ipv4("0.0.0.0", DUNSTBLICK_DEFAULT_PORT)))
        throw xcept::io_error("Failed to bind multicast socket.");

    ip_mreq mcast_request;
    mcast_request.imr_interface.s_addr = INADDR_ANY;
    mcast_request.imr_multiaddr.s_addr = inet_addr(DUNSTBLICK_MULTICAST_GROUP);
    if (not multicast_sock.set_option<ip_mreq>(SOL_SOCKET, IP_ADD_MEMBERSHIP, mcast_request))
        throw xcept::io_error("Failed to join multicast group.");

    // check("udp loop") = multicast_sock.set_option<int>(SOL_SOCKET,
    // IP_MULTICAST_LOOP, 1);

    this->worker_thread = std::thread(provider_mainloop, this);
}

dunstblick_Provider::~dunstblick_Provider()
{
    shutdown_request.clear();
    worker_thread.join();

    //    ip_mreq mcast_request;
    //    mcast_request.imr_interface.s_addr = INADDR_ANY;
    //    mcast_request.imr_multiaddr.s_addr =
    //    inet_addr(DUNSTBLICK_MULTICAST_GROUP); if(not
    //    multicast_sock.set_option<ip_mreq>(SOL_SOCKET, IP_DROP_MEMBERSHIP,
    //    mcast_request))
    //        perror("Failed to leave multicast group");
}

dunstblick_Connection::dunstblick_Connection(dunstblick_Provider * provider,
                                             xnet::socket && _sock,
                                             xnet::endpoint const & ep) :
    sock(std::move(_sock)),
    remote(ep),
    state(READ_HEADER),
    is_initialized(false),
    disconnect_reason(std::nullopt),
    provider(provider)
{
    assert(provider != nullptr);
    fprintf(stderr, "connection from %s\n", to_string(remote).c_str());
}

dunstblick_Connection::~dunstblick_Connection()
{
    fprintf(stderr, "connection lost to %s\n", to_string(remote).c_str());
}

void dunstblick_Connection::drop(dunstblick_DisconnectReason reason)
{
    if (this->disconnect_reason)
        return; // already dropped
    this->disconnect_reason = reason;
    fprintf(stderr, "dropped connection to %s: %u\n", to_string(remote).c_str(), reason);
    fflush(stderr);
}

void dunstblick_Connection::send_data()
{
    switch (this->state) {
        case SEND_RESOURCES: {

            mutex_guard lock{provider->resource_lock};

            auto const resource_id = required_resources.at(resource_send_index);
            auto const & resource = provider->resources.at(resource_id);

            if (resource_send_offset == 0) {

                TcpResourceHeader header;
                header.id = resource_id;
                header.size = resource.data.size();

                xnet::socket_ostream stream{this->sock};
                stream.write<TcpResourceHeader>(header);
            }

            size_t rest = resource.data.size() - resource_send_offset;

            ssize_t len;
            do {
                len = this->sock.write(resource.data.data() + resource_send_offset, rest);
                if (len < 0)
                    return; // this was a send error

                // while nothing could be transmit:
                // try retransmitting
            } while (len == 0);
            resource_send_offset += size_t(len);

            if (resource_send_offset == resource.data.size()) {
                // sending was completed
                resource_send_index += 1;
                resource_send_offset = 0;
                if (resource_send_index == required_resources.size()) {
                    // sending is done!
                    state = READY;

                    // handshake phase is complete,
                    // switch over to
                    is_initialized = true;
                }
            }

            break;
        }

        default:
            // we don't need to send anything by-default
            return;
    }
}

void dunstblick_Connection::push_data(const void * blob, size_t length)
{
    size_t static constexpr max_buffer_limit = 5 * 1024 * 1024; // 5 MeBiByte

    if (receive_buffer.size() + length >= max_buffer_limit) {
        return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
    }

    size_t const offset = receive_buffer.size();
    receive_buffer.resize(offset + length);
    memcpy(receive_buffer.data() + offset, blob, length);

    fprintf(stderr,
            "read %lu bytes from %s into buffer of %lu\n",
            length,
            to_string(remote).c_str(),
            receive_buffer.size());

    while (receive_buffer.size() > 0) {
        size_t consumed_size = 0;
        switch (state) {
            case READ_HEADER: {
                if (receive_buffer.size() > sizeof(TcpConnectHeader)) {
                    // Drop if we received too much data.
                    // Server is not allowed to send more than the actual
                    // connect header.
                    return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
                }
                if (receive_buffer.size() < sizeof(TcpConnectHeader)) {
                    // not yet enough data
                    return;
                }
                assert(receive_buffer.size() == sizeof(TcpConnectHeader));

                auto const & net_header = *reinterpret_cast<TcpConnectHeader const *>(receive_buffer.data());

                if (net_header.magic != TcpConnectHeader::real_magic)
                    return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
                if (net_header.protocol_version != TcpConnectHeader::current_protocol_version)
                    return drop(DUNSTBLICK_DISCONNECT_PROTOCOL_MISMATCH);

                this->header.password = extract_string(net_header.password);
                this->header.clientName = extract_string(net_header.name);
                this->header.capabilities = dunstblick_ClientCapabilities(net_header.capabilities);

                this->screenResolution.w = net_header.screenSizeX;
                this->screenResolution.h = net_header.screenSizeY;

                {
                    mutex_guard lock{provider->resource_lock};
                    xnet::socket_ostream stream(sock);

                    TcpConnectResponse response;
                    response.success = 1;
                    response.resourceCount = provider->resources.size();

                    stream.write<TcpConnectResponse>(response);

                    for (auto const & kv : provider->resources) {
                        auto const & resource = kv.second;
                        TcpResourceDescriptor descriptor;
                        descriptor.id = resource.id;
                        descriptor.size = resource.data.size();
                        descriptor.type = resource.type;
                        memcpy(descriptor.md5sum, resource.hash.data(), 16);
                        stream.write<TcpResourceDescriptor>(descriptor);
                    }
                }

                state = READ_REQUIRED_RESOURCE_HEADER;

                consumed_size = sizeof(TcpConnectHeader);
                break;
            }

            case READ_REQUIRED_RESOURCE_HEADER: {

                if (receive_buffer.size() < sizeof(TcpResourceRequestHeader))
                    return;

                auto const & header = *reinterpret_cast<TcpResourceRequestHeader const *>(receive_buffer.data());

                required_resource_count = header.request_count;

                this->required_resources.clear();
                state = READ_REQUIRED_RESOURCES;

                consumed_size = sizeof(TcpResourceRequestHeader);

                break;
            }

            case READ_REQUIRED_RESOURCES: {
                if (receive_buffer.size() < sizeof(TcpResourceRequest))
                    return;

                auto const & request = *reinterpret_cast<TcpResourceRequest const *>(receive_buffer.data());

                this->required_resources.emplace_back(request.id);

                assert(required_resources.size() <= required_resource_count);
                if (required_resources.size() == required_resource_count) {

                    if (receive_buffer.size() > sizeof(TcpResourceRequest)) {
                        // If excess data was sent, we drop the connection
                        return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
                    }

                    resource_send_index = 0;
                    resource_send_offset = 0;
                    state = SEND_RESOURCES;
                }

                // wait for a packet of all required resources

                consumed_size = sizeof(TcpResourceRequest);
                break;
            }

            case SEND_RESOURCES: {
                // we are currently uploading all resources,
                // receiving anything here would be protocol violation
                return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
            }

            case READY: {
                // Use normal dunstblick protocol decoding here

                fprintf(stderr, "read %lu bytes from %s in READY state\n", length, to_string(remote).c_str(), state);

                break;
            }
        }
        assert(consumed_size > 0);
        assert(consumed_size <= receive_buffer.size());
        receive_buffer.erase(receive_buffer.begin(), receive_buffer.begin() + consumed_size);
    }
}

struct FDSet
{
    fd_set set;
    int max_fd;

    FDSet()
    {
        FD_ZERO(&set);
        max_fd = 0;
    }

    void add(int fd)
    {
        max_fd = std::max(max_fd, fd);
        FD_SET(fd, &set);
    }

    bool check(int fd) const
    {
        return FD_ISSET(fd, &set);
    }
};

static void provider_mainloop(dunstblick_Provider * provider)
{
    auto const tcp_listener_ep = provider->tcp_sock.get_local_endpoint();

    fprintf(stderr, "listening on %s\n", xnet::to_string(tcp_listener_ep).c_str());

    while (provider->shutdown_request.test_and_set()) {
        FDSet read_fds, write_fds;
        read_fds.add(provider->multicast_sock.handle);
        read_fds.add(provider->tcp_sock.handle);

        for (auto const & connection : provider->pending_connections) {
            read_fds.add(connection.sock.handle);
            write_fds.add(connection.sock.handle);
        }
        for (auto const & connection : provider->established_connections) {
            read_fds.add(connection.sock.handle);
        }

        timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 10000;

        int result = select(read_fds.max_fd + 1, &read_fds.set, &write_fds.set, nullptr, &timeout);
        if (result < 0) {
            perror("failed to select:");
        }

        std::array<uint8_t, 4096> blob;

        auto const readAndPushToConnection = [&](dunstblick_Connection & con) -> void {
            if (not read_fds.check(con.sock.handle))
                return;

            ssize_t len = con.sock.read(blob.data(), blob.size());
            if (len < 0) {
                con.disconnect_reason = DUNSTBLICK_DISCONNECT_NETWORK_ERROR;
                perror("failed to read from connection");
            } else if (len == 0) {
                con.disconnect_reason = DUNSTBLICK_DISCONNECT_QUIT;
            } else if (len > 0) {
                con.push_data(blob.data(), size_t(len));
            }
        };

        for (auto & connection : provider->pending_connections) {
            readAndPushToConnection(connection);
        }
        for (auto & connection : provider->established_connections) {
            readAndPushToConnection(connection);
        }

        for (auto & connection : provider->pending_connections) {
            if (not write_fds.check(connection.sock.handle))
                continue;
            connection.send_data();
        }

        if (read_fds.check(provider->multicast_sock.handle)) {
            fflush(stdout);

            UdpBaseMessage message;

            auto const [ssize, sender] = provider->multicast_sock.read_from(&message, sizeof message);
            if (ssize < 0) {
                perror("read udp failed");
            } else {
                size_t size = size_t(ssize);
                if (size < sizeof(message.header)) {
                    fprintf(stderr, "udp message too small…\n");
                } else {
                    if (message.header.magic == UdpHeader::real_magic) {
                        switch (message.header.type) {
                            case UDP_DISCOVER: {
                                if (size >= sizeof(message.discover)) {
                                    UdpDiscoverResponse response;
                                    response.header = UdpHeader::create(UDP_RESPOND_DISCOVER);
                                    response.tcp_port = uint16_t(tcp_listener_ep.port());
                                    response.length = provider->discovery_name.size();

                                    strncpy(response.name.data(),
                                            provider->discovery_name.c_str(),
                                            response.name.size());

                                    fprintf(stderr, "response to %s\n", xnet::to_string(sender).c_str());
                                    fflush(stderr);

                                    ssize_t const sendlen =
                                        provider->multicast_sock.write_to(sender, &response, sizeof response);
                                    if (sendlen < 0) {
                                        perror("failed to send discovery response");
                                    } else if (sendlen < sizeof(response)) {
                                        fprintf(stderr,
                                                "expected to send %lu bytes, got %ld\n",
                                                sizeof(response),
                                                sendlen);
                                    }
                                } else {
                                    fprintf(stderr, "expected %lu bytes, got %ld\n", sizeof(message.discover), size);
                                }
                                break;
                            }
                            case UDP_RESPOND_DISCOVER: {
                                if (size >= sizeof(message.discover_response)) {
                                    fprintf(stderr, "got udp response\n");
                                } else {
                                    fprintf(stderr,
                                            "expected %lu bytes, got %ld\n",
                                            sizeof(message.discover_response),
                                            size);
                                }
                                break;
                            }
                            default:
                                fprintf(stderr, "invalid packet type: %u\n", message.header.type);
                        }
                    } else {
                        fprintf(stderr,
                                "Invalid packet magic: %02X%02X%02X%02X\n",
                                message.header.magic[0],
                                message.header.magic[1],
                                message.header.magic[2],
                                message.header.magic[3]);
                    }
                }
            }
        }
        if (read_fds.check(provider->tcp_sock.handle)) {
            auto [socket, endpoint] = provider->tcp_sock.accept();

            provider->pending_connections.emplace_back(provider, std::move(socket), endpoint);
        }

        provider->pending_connections.remove_if(
            [&](dunstblick_Connection & con) -> bool { return con.disconnect_reason.has_value(); });

        // Sorts connections from "pending" to "ready"
        provider->pending_connections.sort(
            [](dunstblick_Connection const & a, dunstblick_Connection const & b) -> bool {
                return a.is_initialized < b.is_initialized;
            });
        {
            auto it = provider->pending_connections.begin();
            auto end = provider->pending_connections.end();
            while (it != end and not it->is_initialized) {
                std::advance(it, 1);
            }
            if (it != end) {
                // we found connections that are ready
                auto const start = it;

                do {
                    provider->onConnected.invoke(provider,
                                                 &(*it),
                                                 it->header.clientName.c_str(),
                                                 it->header.password.c_str(),
                                                 it->screenResolution,
                                                 it->header.capabilities);

                    std::advance(it, 1);
                } while (it != end);

                // Now transfer all established connections to the other set.
                provider->established_connections.splice(provider->established_connections.begin(),
                                                         provider->pending_connections,
                                                         start,
                                                         end);
            }
        }

        provider->established_connections.remove_if([&](dunstblick_Connection & con) -> bool {
            if (not con.disconnect_reason)
                return false;
            provider->onDisconnected.invoke(provider, &con, *con.disconnect_reason);
            return true;
        });
    }
    for (auto & connection : provider->established_connections) {

        fprintf(stderr,
                "Client disconnected callback:\n"
                "\tend point: %s\n"
                "\treason:    %u\n",
                to_string(connection.remote).c_str(),
                *connection.disconnect_reason);

        provider->onDisconnected.invoke(provider, &connection, *connection.disconnect_reason);

        dunstblick_CloseConnection(&connection, "The provider has been shut down.");
    }
}

/*******************************************************************************
 * Provider Implementation *
 *******************************************************************************/

dunstblick_Provider * dunstblick_OpenProvider(const char * discoveryName)
{
    if (discoveryName == nullptr)
        return nullptr;
    if (strlen(discoveryName) > DUNSTBLICK_MAX_APP_NAME_LENGTH)
        return nullptr;
    try {
        return new dunstblick_Provider(discoveryName);
    } catch (xcept::io_error const & err) {
        fprintf(stderr, "%s\n", err.what());
        fflush(stderr);
        return nullptr;
    } catch (std::bad_alloc) {
        return nullptr;
    }
}

void dunstblick_CloseProvider(dunstblick_Provider * provider)
{
    if (provider != nullptr)
        delete provider;
}

dunstblick_Error dunstblick_SetConnectedCallback(dunstblick_Provider * provider,
                                                 dunstblick_ConnectedCallback callback,
                                                 void * userData)
{
    if (provider == nullptr)
        return DUNSTBLICK_ERROR_INVALID_ARG;
    mutex_guard _{provider->mutex};
    provider->onConnected = {callback, userData};
    return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_SetDisconnectedCallback(dunstblick_Provider * provider,
                                                    dunstblick_DisconnectedCallback callback,
                                                    void * userData)
{
    if (provider == nullptr)
        return DUNSTBLICK_ERROR_INVALID_ARG;
    mutex_guard _{provider->mutex};
    provider->onDisconnected = {callback, userData};
    return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_AddResource(dunstblick_Provider * provider,
                                        dunstblick_ResourceID resourceID,
                                        dunstblick_ResourceKind type,
                                        const void * data,
                                        size_t length)
{
    if (provider == nullptr)
        return DUNSTBLICK_ERROR_INVALID_ARG;
    if (data == nullptr)
        return DUNSTBLICK_ERROR_INVALID_ARG;
    if (length == 0)
        return DUNSTBLICK_ERROR_INVALID_ARG;

    mutex_guard _{provider->resource_lock};

    auto it = provider->resources.find(resourceID);
    if (it == provider->resources.end()) {
        StoredResource resource;
        resource.id = resourceID;
        resource.type = type;
        resource.data.resize(length);
        memcpy(resource.data.data(), data, length);
        resource.update_hash();

        auto [it, emplaced] = provider->resources.emplace(resourceID, std::move(resource));
        assert(emplaced);
    } else {
        auto & resource = it->second;
        assert(resource.id == resourceID);
        resource.type = type;
        resource.data.resize(length);
        memcpy(resource.data.data(), data, length);
        resource.update_hash();
    }
    return DUNSTBLICK_ERROR_NONE;
}

dunstblick_Error dunstblick_RemoveResource(dunstblick_Provider * provider, dunstblick_ResourceID resourceID)
{
    if (provider == nullptr)
        return DUNSTBLICK_ERROR_INVALID_ARG;
    mutex_guard _{provider->resource_lock};
    provider->resources.erase(resourceID);
    return DUNSTBLICK_ERROR_NONE;
}

/*******************************************************************************
 * Connection Implementation *
 *******************************************************************************/

void dunstblick_CloseConnection(dunstblick_Connection * connection, const char * reason)
{
    if (connection == nullptr)
        return;
    if (reason == nullptr)
        reason = "The provider closed the connection.";

    mutex_guard _{connection->mutex};
    if (connection->disconnect_reason)
        return;

    connection->disconnect_reason = DUNSTBLICK_DISCONNECT_SHUTDOWN;

    // TODO: Send real disconnect packet here
    connection->sock.write(reason, strlen(reason));
}

const char * dunstblick_GetClientName(dunstblick_Connection * connection)
{
    if (connection == nullptr)
        return nullptr;
    return connection->header.clientName.c_str();
}

dunstblick_Size dunstblick_GetDisplaySize(dunstblick_Connection * connection)
{
    if (connection == nullptr)
        return dunstblick_Size{0, 0};
    return connection->screenResolution;
}

/*******************************************************************************
 * Object Implementation *
 *******************************************************************************/

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

for (auto const & entry : xnet::dns::resolve(host,
std::to_string(portNumber), SOCK_STREAM))
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


dunstblick_Error dunstblick_PumpEvents(dunstblick_Connection * con,
dunstblick_EventHandler const * eha, void * context)
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

dunstblick_Error dunstblick_UploadResource(dunstblick_Connection * con,
dunstblick_ResourceID rid, dunstblick_ResourceKind kind, const void * data,
size_t length)
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

dunstblick_Object * dunstblick_BeginChangeObject(dunstblick_Connection * con,
dunstblick_ObjectID id)
{
if(con == nullptr)
    return nullptr;
if(id == 0)
    return nullptr;

auto * obj = new dunstblick_Object(con);
obj->commandbuffer.write_id(id);
return obj;
}

dunstblick_Error dunstblick_RemoveObject(dunstblick_Connection * con,
dunstblick_ObjectID oid)
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

dunstblick_Error dunstblick_SetView(dunstblick_Connection * con,
dunstblick_ResourceID rid)
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

dunstblick_Error dunstblick_SetRoot(dunstblick_Connection * con,
dunstblick_ObjectID oid)
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

dunstblick_Error dunstblick_SetProperty(dunstblick_Connection * con,
dunstblick_ObjectID oid, dunstblick_PropertyName name, const dunstblick_Value *
value)
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

dunstblick_Error dunstblick_Clear(dunstblick_Connection * con,
dunstblick_ObjectID oid, dunstblick_PropertyName name)
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

dunstblick_Error dunstblick_InsertRange(dunstblick_Connection * con,
dunstblick_ObjectID oid, dunstblick_PropertyName name, size_t index, size_t
count, const dunstblick_ObjectID * values)
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

dunstblick_Error dunstblick_RemoveRange(dunstblick_Connection * con,
dunstblick_ObjectID oid, dunstblick_PropertyName name, size_t index, size_t
count)
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

dunstblick_Error dunstblick_MoveRange(dunstblick_Connection * con,
dunstblick_ObjectID oid, dunstblick_PropertyName name, size_t indexFrom, size_t
indexTo, size_t count)
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



dunstblick_Error dunstblick_SetObjectProperty(dunstblick_Object * obj,
dunstblick_PropertyName name, dunstblick_Value const * value)
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

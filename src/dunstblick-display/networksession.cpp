#include "networksession.hpp"

#include <xnet/select>
#include <xnet/socket_stream>

#include "dunstblick-internal.hpp"
#include <xcept>
#include <xlog>

#include "data-writer.hpp"

NetworkSession::NetworkSession(const xnet::endpoint & target) : sock(target.family(), SOCK_STREAM, 0)
{
    if (not sock.connect(target))
        throw xcept::io_error("could not connect to " + to_string(target));

    xnet::socket_stream stream{sock};

    TcpConnectHeader connect_header;
    connect_header.magic = TcpConnectHeader::real_magic;
    connect_header.protocol_version = TcpConnectHeader::current_protocol_version;
    connect_header.name = std::array<char, 32>{"Test Client"};
    connect_header.password = std::array<char, 32>{""};
    connect_header.screenSizeX = 320;
    connect_header.screenSizeY = 240;
    connect_header.capabilities = DUNSTBLICK_CAPS_KEYBOARD;
    stream.write(connect_header);

    auto const connect_response = stream.read<TcpConnectResponse>();
    if (connect_response.success != 1)
        throw xcept::io_error("failed to authenticate client.");

    std::map<dunstblick_ResourceID, TcpResourceDescriptor> resources;
    for (size_t i = 0; i < connect_response.resourceCount; i++) {

        auto const res = stream.read<TcpResourceDescriptor>();

        resources.emplace(res.id, res);

        fprintf(stdout,
                "Resource[%lu]:\n"
                "\tid:   %u\n"
                "\ttype: %u\n"
                "\tsize: %u\n"
                "\thash: %02X%02X%02X%02X%02X%02X%02X%02X\n",
                i,
                res.id,
                res.type,
                res.size,
                res.siphash[0],
                res.siphash[1],
                res.siphash[2],
                res.siphash[3],
                res.siphash[4],
                res.siphash[5],
                res.siphash[6],
                res.siphash[7]
                // res.md5sum[8],
                // res.md5sum[9],
                // res.md5sum[10],
                // res.md5sum[11],
                // res.md5sum[12],
                // res.md5sum[13],
                // res.md5sum[14],
                // res.md5sum[15]
        );
    }

    TcpResourceRequestHeader request_header;
    request_header.request_count = resources.size();
    stream.write(request_header);

    // request half of the resources
    for (auto const & pair : resources) {
        TcpResourceRequest request;
        request.id = pair.second.id;
        stream.write(request);
    }

    for (size_t i = 0; i < request_header.request_count; i++) {
        auto const header = stream.read<TcpResourceHeader>();

        fprintf(stdout, "Receiving resource %u (%u bytes)…\n", header.id, header.size);

        std::vector<uint8_t> bytes;
        bytes.resize(header.size);

        stream.read(bytes.data(), bytes.size());

        uploadResource(UIResourceID(header.id), ResourceKind(resources.at(header.id).type), bytes.data(), bytes.size());
    }
}

void NetworkSession::update()
{
    do_communication();
}

void NetworkSession::trigger_event(EventID cid, WidgetName widget)
{
    if (cid.is_null()) // ignore empty callbacks
        return;

    CommandBuffer buffer{ServerMessageType::eventCallback};
    buffer.write_id(cid.value);
    buffer.write_id(widget.value);

    send_message(buffer);
}

void NetworkSession::trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value)
{
    if (oid.is_null())
        return;
    if (name.is_null())
        return;
    if (value.index() == 0)
        return;

    CommandBuffer buffer{ServerMessageType::propertyChanged};
    buffer.write_id(oid.value);
    buffer.write_id(name.value);
    buffer.write_value(value, true);

    send_message(buffer);
}

void NetworkSession::send_message(CommandBuffer const & buffer)
{
    std::lock_guard _{send_lock};
    xnet::socket_ostream stream{this->sock};

    auto const len = gsl::narrow<uint32_t>(buffer.buffer.size());

    stream.write<uint32_t>(len);
    stream.write(buffer.buffer.data(), len);
}

void NetworkSession::do_communication()
{
    Packet packet;

    while (true) {

        xnet::socket_set read_set;
        read_set.add(this->sock);
        xnet::select(read_set, xstd::nullopt, xstd::nullopt, std::chrono::microseconds(0));
        if (not read_set.contains(this->sock))
            break;

        try {

            xnet::socket_istream stream{this->sock};

            auto const length = stream.read<uint32_t>();

            packet.resize(length);
            stream.read(packet.data(), packet.size());
        } catch (xcept::end_of_stream) {
            this->is_active = false;
            return;
        }

        parse_and_exec_msg(packet);
    }
}

void NetworkSession::parse_and_exec_msg(Packet const & msg)
{
    InputStream stream(msg.data(), msg.size());

    auto const msgType = ClientMessageType(stream.read_byte());
    switch (msgType) {
        case ClientMessageType::uploadResource: // (rid, kind, data)
        {
            auto resource = stream.read_id<UIResourceID>();
            auto kind = stream.read_enum<ResourceKind>();

            auto const [data, len] = stream.read_to_end();

            uploadResource(resource, kind, data, len);
            break;
        }

        case ClientMessageType::addOrUpdateObject: // (obj)
        {
            auto obj = stream.read_object();
            addOrUpdateObject(std::move(obj));
            break;
        }

        case ClientMessageType::removeObject: // (oid)
        {
            auto const oid = stream.read_id<ObjectID>();
            removeObject(oid);
            break;
        }

        case ClientMessageType::setView: // (rid)
        {
            auto const rid = stream.read_id<UIResourceID>();
            setView(rid);
            break;
        }

        case ClientMessageType::setRoot: // (oid)
        {
            auto const oid = stream.read_id<ObjectID>();
            setRoot(oid);
            break;
        }

        case ClientMessageType::setProperty: // (oid, name, value)
        {
            auto const oid = stream.read_id<ObjectID>();
            auto const propName = stream.read_id<PropertyName>();
            auto const type = stream.read_enum<UIType>();
            auto const value = stream.read_value(type);

            setProperty(oid, propName, value);
            break;
        }

        case ClientMessageType::clear: // (oid, name)
        {
            auto const oid = stream.read_id<ObjectID>();
            auto const propName = stream.read_id<PropertyName>();
            clear(oid, propName);
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
            for (size_t i = 0; i < count; i++)
                refs.emplace_back(stream.read_id<ObjectID>());
            insertRange(oid, propName, index, count, refs.data());
            break;
        }

        case ClientMessageType::removeRange: // (oid, name, index, count) // manipulate lists
        {
            auto const oid = stream.read_id<ObjectID>();
            auto const propName = stream.read_id<PropertyName>();
            auto const index = stream.read_uint();
            auto const count = stream.read_uint();
            removeRange(oid, propName, index, count);
            break;
        }

        case ClientMessageType::moveRange: // (oid, name, indexFrom, indexTo, count) // manipulate lists
        {
            auto const oid = stream.read_id<ObjectID>();
            auto const propName = stream.read_id<PropertyName>();
            auto const indexFrom = stream.read_uint();
            auto const indexTo = stream.read_uint();
            auto const count = stream.read_uint();
            moveRange(oid, propName, indexFrom, indexTo, count);
            break;
        }

        default:
            xlog::log(xlog::error) << "received message of unknown type: " << std::to_string(uint8_t(msgType));
            break;
    }
}

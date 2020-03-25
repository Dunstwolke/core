#include "session.hpp"

#include "rendercontext.hpp"
#include <xcept>
#include <xlog>
#include <xnet/select>
#include <xnet/socket_stream>

#include <SDL_image.h>

#include "widget.hpp"

#include <dunstblick-internal.hpp>

extern SDL_Rect screen_rect;

void Session::trigger_callback(CallbackID cid)
{
    if (cid.is_null()) // ignore empty callbacks
        return;

    CommandBuffer buffer{ServerMessageType::eventCallback};
    buffer.write_id(cid.value);

    send_message(buffer);
}

void Session::trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value)
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

void Session::parse_and_exec_msg(Packet const & msg)
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

Session::Session(const xnet::endpoint & target) : sock(target.family(), SOCK_STREAM, 0)
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
        auto & res = resources[i];
        res = stream.read<TcpResourceDescriptor>();

        resources.emplace(res.id, res);

        fprintf(stdout,
                "Resource[%lu]:\n"
                "\tid:   %u\n"
                "\ttype: %u\n"
                "\tsize: %u\n"
                "\thash: %02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X\n",
                i,
                res.id,
                res.type,
                res.size,
                res.md5sum[0],
                res.md5sum[1],
                res.md5sum[2],
                res.md5sum[3],
                res.md5sum[4],
                res.md5sum[5],
                res.md5sum[6],
                res.md5sum[7],
                res.md5sum[8],
                res.md5sum[9],
                res.md5sum[10],
                res.md5sum[11],
                res.md5sum[12],
                res.md5sum[13],
                res.md5sum[14],
                res.md5sum[15]);
    }

    TcpResourceRequestHeader request_header;
    request_header.request_count = resources.size();
    stream.write(request_header);

    // request half of the resources
    for (size_t i = 0; i < request_header.request_count; i++) {
        TcpResourceRequest request;
        request.id = resources.at(i).id;
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

Session::~Session() {}

void Session::do_communication()
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

void Session::send_message(CommandBuffer const & buffer)
{
    std::lock_guard _{send_lock};
    xnet::socket_ostream stream{this->sock};

    auto const len = gsl::narrow<uint32_t>(buffer.buffer.size());

    stream.write<uint32_t>(len);
    stream.write(buffer.buffer.data(), len);
}

void Session::uploadResource(UIResourceID id, ResourceKind kind, const void * data, size_t len)
{
    switch (kind) {
        case ResourceKind::layout: {
            set_resource(id, LayoutResource(reinterpret_cast<uint8_t const *>(data), len));
            break;
        }

        case ResourceKind::bitmap: {
            auto * tex = IMG_LoadTexture_RW(context().renderer, SDL_RWFromConstMem(data, gsl::narrow<int>(len)), 1);

            if (tex == nullptr) {
                xlog::log(xlog::error) << "could not load bitmap for resource " << id.value << ": " << SDL_GetError();
                return;
            }

            set_resource(id, BitmapResource(sdl2::texture(std::move(tex))));
            break;
        }

        case ResourceKind::drawing:
            assert(false and "not implemented yet!");
    }
}

void Session::removeObject(ObjectID id)
{
    destroy_object(id);
}

void Session::addOrUpdateObject(Object && obj)
{
    add_or_update_object(std::move(obj));
}

void Session::update_layout()
{
    if (not root_widget)
        return;
    root_widget->updateBindings(root_object);
    root_widget->updateWantedSize();
    root_widget->layout(screen_rect);
}

void Session::setView(UIResourceID id)
{
    root_widget = load_widget(id);

    // focused widgets are destroyed, so remove the reference here!
    keyboard_focused_widget = nullptr;
    mouse_focused_widget = nullptr;

    update_layout();
}

void Session::setRoot(ObjectID id)
{
    auto ref = ObjectRef{id};
    if (ref) {
        root_object = ref;
        update_layout();
    }
}

void Session::ui_set_keyboard_focus(Widget * widget)
{
    if (keyboard_focused_widget == widget)
        return;

    if (keyboard_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_LOST_KEYBOARD_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        keyboard_focused_widget->processEvent(e);
    }
    keyboard_focused_widget = widget;
    if (keyboard_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_GOT_KEYBOARD_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        keyboard_focused_widget->processEvent(e);
    }
}

void Session::ui_set_mouse_focus(Widget * widget)
{
    if (mouse_focused_widget == widget)
        return;

    if (mouse_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_LOST_MOUSE_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        mouse_focused_widget->processEvent(e);
    }
    mouse_focused_widget = widget;
    if (mouse_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_GOT_MOUSE_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        mouse_focused_widget->processEvent(e);
    }
}

void Session::setProperty(ObjectID oid, PropertyName propName, const UIValue & value)
{
    auto const type = UIType(value.index());
    if (auto obj = ObjectRef{oid}.try_resolve(); obj) {
        if (auto prop = obj->get(propName); prop) {
            if (prop->type == type) {
                prop->value = value;
            } else {
                xlog::log(xlog::error) << "property " << propName.value << " of object  " << oid.value << " is of type "
                                       << to_string(prop->type) << " but " << to_string(type) << " was provided!";
            }
        } else {
            xlog::log(xlog::error) << "object " << oid.value << " does not have the property " << propName.value << "!";
        }
    } else {
        xlog::log(xlog::error) << "object " << oid.value << " does not exist!";
    }
}

static inline xstd::optional<ObjectList &> get_list(ObjectID oid, PropertyName name)
{
    if (auto obj = ObjectRef{oid}.try_resolve(); obj) {
        if (auto prop = obj->get(name); prop) {
            if (prop->type == UIType::objectlist) {
                return std::get<ObjectList>(prop->value);
            } else {
                xlog::log(xlog::error) << "property " << name.value << " of object  " << oid.value << " is of type "
                                       << to_string(prop->type) << " instead of type objectlist!";
            }
        } else {
            xlog::log(xlog::error) << "object " << oid.value << " does not have the property " << name.value << "!";
        }
    } else {
        xlog::log(xlog::error) << "object " << oid.value << " does not exist!";
    }
    return xstd::nullopt;
}

void Session::clear(ObjectID obj, PropertyName prop)
{
    if (auto list = get_list(obj, prop); list) {
        list->clear();
    }
}

void Session::insertRange(ObjectID obj, PropertyName prop, size_t index, size_t count, const ObjectRef * value)
{
    if (auto list = get_list(obj, prop); list) {
        for (size_t i = 0; i < count; i++, index++) {
            list->emplace((index >= list->size()) ? list->end() : list->begin() + gsl::narrow<ssize_t>(index),
                          value[i]);
        }
    }
}

void Session::removeRange(ObjectID obj, PropertyName prop, size_t index, size_t count)
{
    if (auto list = get_list(obj, prop); list) {
        if (list->empty())
            return;
        for (size_t i = 0; (i < count) and (index < list->size()); i++, index++) {
            list->erase(list->begin() + gsl::narrow<ssize_t>(index));
        }
    }
}

void Session::moveRange(ObjectID obj, PropertyName prop, size_t indexFrom, size_t indexTo, size_t count)
{
    if (auto list = get_list(obj, prop); list) {
        assert(false and "not implemented yet!");
    }
}

Widget * Session::get_mouse_widget(int x, int y)
{
    if (not root_widget)
        return nullptr;
    else if (Widget::capturingWidget)
        return Widget::capturingWidget;
    else
        return root_widget->hitTest(x, y);
}

static std::unique_ptr<Widget> deserialize_widget(UIWidget widgetType, InputStream & stream)
{
    auto widget = Widget::create(widgetType);
    assert(widget);

    UIProperty property;
    do {
        bool isBinding;
        std::tie(property, isBinding) = stream.read_property_enum();
        if (property != UIProperty::invalid) {
            if (isBinding) {
                auto const name = PropertyName(stream.read_uint());
                widget->setPropertyBinding(property, name);
            } else {
                auto const value = stream.read_value(getPropertyType(property));
                widget->setProperty(property, value);
            }
        }
    } while (property != UIProperty::invalid);

    UIWidget childType;
    do {
        childType = stream.read_enum<UIWidget>();
        if (childType != UIWidget::invalid)
            widget->children.emplace_back(deserialize_widget(childType, stream));
    } while (childType != UIWidget::invalid);

    return widget;
}

static std::unique_ptr<Widget> deserialize_widget(InputStream & stream)
{
    auto const widgetType = stream.read_enum<UIWidget>();
    return deserialize_widget(widgetType, stream);
}

/// loads a widget from a given resource ID or throws.
std::unique_ptr<Widget> Session::load_widget(UIResourceID id)
{
    if (auto resource = find_resource(id); resource) {
        if (resource->index() != int(ResourceKind::layout))
            throw std::runtime_error("invalid resource: wrong kind!");

        auto const & layout = std::get<LayoutResource>(*resource);

        InputStream stream = layout.get_stream();

        auto widget = deserialize_widget(stream);
        widget->templateID = id;
        return widget;
    } else {
        throw std::runtime_error("could not find the right resource!");
    }
}

xstd::optional<Resource const &> Session::find_resource(UIResourceID id)
{
    if (auto it = resources.find(id); it != resources.end())
        return it->second;
    else
        return xstd::nullopt;
}

void Session::set_resource(UIResourceID id, Resource && resource)
{
    if (auto it = resources.find(id); it != resources.end())
        it->second = std::move(resource);
    else
        resources.emplace(id, std::move(resource));
}

#include <SDL.h>
#include <SDL_image.h>
#include <filesystem>
#include <sdl2++/renderer>
#include <vector>

#include "layouts.hpp"
#include "resources.hpp"
#include "types.hpp"
#include "widget.hpp"
#include "widgets.hpp"

#include "inputstream.hpp"

#include "enums.hpp"
#include "protocol.hpp"
#include "resources.hpp"
#include "types.hpp"

#include "tcphost.hpp"

#include "session.hpp"

#include "localsession.hpp"
#include "networksession.hpp"

#include <dunstblick-internal.hpp>

static bool shutdown_app_requested = false;

[[noreturn]] static void exit_sdl_error(char const * msg = nullptr)
{
    fprintf(stderr, "%s: %s\n", (msg != nullptr) ? msg : "sdl error", SDL_GetError());
    fflush(stdout);
    fflush(stderr);
    exit(1);
}

static std::unique_ptr<RenderContext> current_rc;

SDL_Rect screen_rect = {0, 0, 0, 0};

RenderContext & context()
{
    return *current_rc;
}

#include <iostream>

static std::ostream & operator<<(std::ostream & stream, std::monostate)
{
    stream << "<NULL>";
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, ObjectRef ref)
{
    stream << "→[" << ref.id.value << "]";
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, EventID cb)
{
    stream << "{" << cb.value << "}";
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, ObjectList const & list)
{
    stream << "[";
    for (auto const & val : list) {
        stream << " " << val;
    }
    stream << " ]";
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, UIMargin)
{
    stream << "<margin>";
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, UIColor col)
{
    stream << std::setw(2) << std::hex << "r=" << col.r << ", g=" << col.g << ", b=" << col.b << ", a=" << col.a;
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, UISize val)
{
    stream << val.w << " × " << val.h;
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, UIPoint val)
{
    stream << val.x << ", " << val.y;
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, UIResourceID)
{
    stream << "<ui resource id>";
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, UISizeList)
{
    stream << "<ui size list>";
    return stream;
}

static std::ostream & operator<<(std::ostream & stream, WidgetName name)
{
    stream << "/" << name.value << "/";
    return stream;
}

static void dump_object(Object const & obj)
{
    std::cout << "Object[" << obj.get_id().value << "]" << std::endl;
    for (auto const & prop : obj.properties) {
        std::cout << "\t[" << prop.first.value << "] : " << to_string(prop.second.type) << " = ";
        std::visit([](auto const & val) { std::cout << val; }, prop.second.value);
        std::cout << std::endl;
    }
}

static Session * current_session;

struct DiscoveredClient
{
    std::string name;
    uint16_t tcp_port;
    xnet::endpoint udp_ep;

    xnet::endpoint create_tcp_endpoint() const
    {
        switch (udp_ep.family()) {
            case AF_INET:
                return xnet::endpoint(udp_ep.get_addr_v4(), tcp_port);
            case AF_INET6:
                return xnet::endpoint(udp_ep.get_addr_v6(), tcp_port);
            default:
                assert(false and "not supported yet");
        }
    }
};

std::vector<DiscoveredClient> discovered_clients;
std::mutex discovered_clients_lock;

void refresh_discovery()
{
    xnet::socket multicast_sock(AF_INET, SOCK_DGRAM, 0);

    // multicast_sock.set_option<int>(SOL_SOCKET, SO_REUSEADDR, 1);
    // multicast_sock.set_option<int>(SOL_SOCKET, SO_BROADCAST, 1);

    // multicast_sock.bind(xnet::parse_ipv4("0.0.0.0", DUNSTBLICK_DEFAULT_PORT));

    // multicast_sock.set_option<int>(SOL_SOCKET, IP_MULTICAST_LOOP, 1);

    auto const multicast_ep = xnet::parse_ipv4(DUNSTBLICK_MULTICAST_GROUP, DUNSTBLICK_DEFAULT_PORT);

    timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 50000;

    multicast_sock.set_option<timeval>(SOL_SOCKET, SO_RCVTIMEO, timeout);

    while (true) {

        std::vector<DiscoveredClient> new_clients;
        for (int i = 0; i < 10; i++) {
            UdpDiscover discoverMsg;
            discoverMsg.header = UdpHeader::create(UDP_DISCOVER);

            ssize_t sendlen = multicast_sock.write_to(multicast_ep, &discoverMsg, sizeof discoverMsg);
            if (sendlen < 0)
                perror("send failed");
            while (true) {
                UdpBaseMessage message;
                auto const [len, sender] = multicast_sock.read_from(&message, sizeof message);
                if (len < 0) {
                    if (errno != EWOULDBLOCK and errno != EAGAIN)
                        perror("receive failed");
                    break;
                }
                if (len >= sizeof(UdpDiscoverResponse) and message.header.type == UDP_RESPOND_DISCOVER) {
                    auto & resp = message.discover_response;
                    if (resp.length < DUNSTBLICK_MAX_APP_NAME_LENGTH)
                        resp.name[resp.length] = 0;
                    else
                        resp.name.back() = 0;

                    DiscoveredClient client;

                    client.name = std::string(resp.name.data());
                    client.tcp_port = resp.tcp_port;
                    client.udp_ep = sender;

                    bool found = false;
                    for (auto const & other : new_clients) {
                        if (client.tcp_port != other.tcp_port)
                            continue;
                        if (client.udp_ep != other.udp_ep)
                            continue;
                        found = true;
                        break;
                    }
                    if (found)
                        continue;
                    new_clients.emplace_back(std::move(client));
                }
            }
        }

        std::sort(new_clients.begin(), new_clients.end(), [](DiscoveredClient const & a, DiscoveredClient const & b) {
            return (a.name < b.name);
        });

        //        size_t idx = 0;
        //        for (auto const & client : new_clients) {
        //            fprintf(stderr,
        //                    "[%lu] %s:\n"
        //                    "\tname: %s\n"
        //                    "\tport: %d\n",
        //                    idx++,
        //                    xnet::to_string(client.udp_ep).c_str(),
        //                    client.name.c_str(),
        //                    client.tcp_port);
        //            fflush(stderr);
        //        }

        {
            std::lock_guard<std::mutex> lock{discovered_clients_lock};
            discovered_clients = std::move(new_clients);
        }
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

static std::vector<std::unique_ptr<Session>> all_sessions;

ObjectID constexpr local_root_obj{1};

UIResourceID constexpr local_discovery_list_item{1};

PropertyName constexpr local_discovery_list{1};
PropertyName constexpr local_app_name{2};
PropertyName constexpr local_app_ip{3};
PropertyName constexpr local_app_port{4};
PropertyName constexpr local_app_id{5};

EventID constexpr local_exit_client_event{1};
EventID constexpr local_open_session_event{2};
EventID constexpr local_close_session_event{3};

constexpr ObjectID local_session_id(size_t index)
{
    return ObjectID(1000 + index);
}

static Session * get_session_for_id(ObjectID value)
{
    if (value.value < 1000)
        return nullptr;
    if (value.value > 1000 + all_sessions.size())
        return nullptr;
    return all_sessions.at(value.value).get();
}

int main()
{
    std::thread discovery_thread(refresh_discovery);

    //////////////////////////////////////////////////////////////////////////////
    if (SDL_Init(SDL_INIT_EVERYTHING) < 0) {
        exit_sdl_error();
    }
    atexit(SDL_Quit);

    if (TTF_Init() < 0) {
        exit_sdl_error();
    }
    atexit(TTF_Quit);

    if (IMG_Init(IMG_INIT_PNG) < 0) {
        exit_sdl_error();
    }
    atexit(IMG_Quit);

    //////////////////////////////////////////////////////////////////////////////

    SDL_Window * window = SDL_CreateWindow("DunstBlick Frontend *FLOAT*",
                                           SDL_WINDOWPOS_CENTERED,
                                           SDL_WINDOWPOS_CENTERED,
                                           800,
                                           600,
                                           SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
    if (window == nullptr) {
        exit_sdl_error();
    }

    SDL_GetWindowSize(window, &screen_rect.w, &screen_rect.h);

    current_rc = std::make_unique<RenderContext>(sdl2::renderer{window},
                                                 "./fonts/Roboto-Regular.ttf",
                                                 "./fonts/CrimsonPro-Regular.ttf",
                                                 "./fonts/SourceCodePro-Regular.ttf");

    context().renderer.setBlendMode(SDL_BLENDMODE_BLEND); // enable alpha blend

    auto const startup = SDL_GetTicks();

    xstd::resource<SDL_Cursor *, SDL_FreeCursor> cursors[SDL_NUM_SYSTEM_CURSORS];
    for (size_t i = 0; i < SDL_NUM_SYSTEM_CURSORS; i++) {
        cursors[i].reset(SDL_CreateSystemCursor(SDL_SystemCursor(i)));
        assert(cursors[i] != nullptr);
    }

    SDL_SystemCursor currentCursor = SDL_SYSTEM_CURSOR_ARROW;
    SDL_SetCursor(cursors[currentCursor].get());

    UIPoint mouse_pos{0, 0};

    // NetworkSession sess{target_endpoint};
    LocalSession sess;

    sess.onEvent = [](EventID event, WidgetName widget) {
        if (event == local_exit_client_event) {
            shutdown_app_requested = true;
        } else if (event == local_open_session_event) {
            DiscoveredClient client;
            {
                std::lock_guard<std::mutex> lock{discovered_clients_lock};
                if (widget.value < 1 or widget.value > discovered_clients.size())
                    return;

                client = discovered_clients.at(widget.value - 1);
            }

            all_sessions.emplace_back(new NetworkSession(client.create_tcp_endpoint()));

        } else if (event == local_close_session_event) {

        } else {
            fprintf(stderr, "Unknown event: %lu, Sender: %lu\n", event.value, widget.value);
            // assert(false and "unhandled event detected");
        }
    };

    // Initialize session objects
    {
        Object obj{local_root_obj};
        obj.add(local_discovery_list, ObjectList{});

        sess.addOrUpdateObject(std::move(obj));

        sess.setRoot(local_root_obj);
    }

    // Initialize session resources
    {
        uint8_t const discovery_list_item[] = {
#include "discovery-list-item.data.h"
        };
        sess.uploadResource(local_discovery_list_item,
                            ResourceKind::layout,
                            discovery_list_item,
                            sizeof discovery_list_item);
    }

    // we "load" our layout by hand and store/modify pointers directly
    // instead of utilizing the resource functions
    sess.root_widget.reset(new TabLayout());
    {
        auto * const menu = new DockLayout();
        menu->tabTitle.set(menu, "Menu");

        auto * const quitLabel = new Label();
        quitLabel->text.set(quitLabel, "Exit");

        auto * const quitButton = new Button();
        quitButton->onClickEvent.set(quitButton, local_exit_client_event);
        quitButton->dockSite.set(quitButton, DockSite::bottom);
        quitButton->children.emplace_back(quitLabel);

        menu->children.emplace_back(quitButton);

        auto * const headerLabel = new Label();
        headerLabel->text.set(headerLabel, "Available Applications");
        headerLabel->font.set(headerLabel, UIFont::serif);

        menu->children.emplace_back(headerLabel);

        auto * const serviceList = new StackLayout();
        serviceList->bindingContext.set(serviceList, ObjectRef{local_root_obj});
        serviceList->childSource.binding = local_discovery_list;
        serviceList->childTemplate.set(serviceList, local_discovery_list_item);

        auto * const serviceScroll = new ScrollView();

        serviceScroll->children.emplace_back(serviceList);

        menu->children.emplace_back(serviceScroll);

        sess.root_widget->children.emplace_back(menu);
    }
    sess.root_widget->initializeRoot(&sess);

    current_session = &sess;

    while (not shutdown_app_requested) {
        for (auto & session : all_sessions) {
            session->update();
        }

        // Remove all destroyed sessions
        {
            auto it = std::remove_if(all_sessions.begin(),
                                     all_sessions.end(),
                                     [](std::unique_ptr<Session> const & item) { return not item->is_active; });
            all_sessions.erase(it, all_sessions.end());
        }

        // Update tab pages
        {
            auto & children = sess.root_widget->children;

            for (size_t i = 0; i < all_sessions.size(); i++) {

                auto const session = all_sessions.at(i).get();

                size_t child_index = i + 1;

                Widget * container;
                if (child_index >= children.size()) {
                    container = new Container();
                    container->tabTitle.set(container, "Unnamed Session " + std::to_string(i));
                    container->widget_context = sess.root_widget->widget_context;
                    children.emplace_back(container);
                } else {
                    container = children.at(child_index).get();
                }

                if (session->root_widget) {
                    auto root = session->root_widget.get();
                    if (container->children.size() == 0)
                        container->children.emplace_back(root);
                    else {
                        container->children.at(0).release();
                        container->children.at(0).reset(root);
                    }
                } else {
                    if (container->children.size() > 0) {
                        assert(container->children.size() == 1);
                        container->children.at(0).release();
                        container->children.clear();
                    }
                }
            }
            while (sess.root_widget->children.size() > all_sessions.size() + 1) {
                // we do evel hackery above and store the same pointer in two
                // unique pointers. We have to make sure that we don't double free it.
                sess.root_widget->children.back().release();
                sess.root_widget->children.pop_back();
            }
        }

        // Update objects in local session
        {
            std::vector<DiscoveredClient> clients;
            {
                std::lock_guard<std::mutex> lock{discovered_clients_lock};
                clients = discovered_clients;
            }

            ObjectList list;
            list.reserve(clients.size());

            for (size_t i = 0; i < clients.size(); i++) {
                auto const id = local_session_id(i);

                Object obj{id};

                obj.add(local_app_name, UIValue(clients[i].name));
                obj.add(local_app_port, UIValue(clients[i].tcp_port));
                obj.add(local_app_ip, UIValue(xnet::to_string(clients[i].udp_ep, false)));
                obj.add(local_app_id, UIValue(WidgetName(i + 1)));

                list.emplace_back(obj);

                sess.addOrUpdateObject(std::move(obj));
            }

            sess.clear(local_root_obj, local_discovery_list);
            sess.insertRange(local_root_obj, local_discovery_list, 0, list.size(), list.data());
        }

        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            switch (e.type) {
                case SDL_QUIT:
                    shutdown_app_requested = true;
                    break;
                case SDL_WINDOWEVENT:
                    switch (e.window.event) {
                        case SDL_WINDOWEVENT_RESIZED:
                            screen_rect.w = e.window.data1;
                            screen_rect.h = e.window.data2;
                            current_session->update_layout();
                            break;
                    }
                    break;

                // keyboard events:
                case SDL_KEYDOWN:
                case SDL_KEYUP:
                case SDL_TEXTEDITING:
                case SDL_TEXTINPUT:
                case SDL_KEYMAPCHANGED: {
                    if (current_session->keyboard_focused_widget != nullptr) {
                        current_session->keyboard_focused_widget->processEvent(e);
                    }
                    break;
                }

                // mouse events:
                case SDL_MOUSEMOTION: {
                    mouse_pos.x = e.motion.x;
                    mouse_pos.y = e.motion.y;
                    if (not current_session->root_widget)
                        break;
                    if (auto * child = current_session->get_mouse_widget(e.motion.x, e.motion.y); child != nullptr) {
                        // only move focus if mouse is not captured
                        if (Widget::capturingWidget == nullptr)
                            current_session->ui_set_mouse_focus(child);
                        child->processEvent(e);
                    }
                    break;
                }

                case SDL_MOUSEBUTTONUP:
                case SDL_MOUSEBUTTONDOWN: {
                    // Only allow left button interaction with all widgets
                    if (e.button.button != SDL_BUTTON_LEFT)
                        break;

                    if (not current_session->root_widget)
                        break;

                    if (auto * child = current_session->get_mouse_widget(e.button.x, e.button.y); child != nullptr) {
                        current_session->ui_set_mouse_focus(child);

                        if ((e.type == SDL_MOUSEBUTTONUP) and child->isKeyboardFocusable())
                            current_session->ui_set_keyboard_focus(child);

                        child->processEvent(e);
                    }
                    break;
                }

                case SDL_MOUSEWHEEL: {
                    if (not current_session->root_widget)
                        break;
                    if (auto * child = current_session->get_mouse_widget(mouse_pos.x, mouse_pos.y); child != nullptr) {
                        current_session->ui_set_mouse_focus(child);

                        child->processEvent(e);
                    }
                    break;
                }
            }
        }

        SDL_SystemCursor nextCursor;
        if (current_session->mouse_focused_widget)
            nextCursor = current_session->mouse_focused_widget->getCursor(mouse_pos);
        else
            nextCursor = SDL_SYSTEM_CURSOR_ARROW;

        if (nextCursor != currentCursor) {
            currentCursor = nextCursor;
            SDL_SetCursor(cursors[currentCursor].get());
        }

        auto const time = SDL_GetTicks() - startup;

        auto const windowFlags = SDL_GetWindowFlags(window);

        // draw UI when window is visible
        if ((windowFlags & (SDL_WINDOW_MINIMIZED | SDL_WINDOW_HIDDEN)) == 0) {
            context().renderer.resetClipRect();
            assert(not context().renderer.isClipEnabled());

            context().renderer.setColor(0x00, 0x00, 0x00, 0xFF);
            context().renderer.fillRect(context().renderer.getViewport());

            current_session->update_layout();

            if (current_session->root_widget) {
                SDL_Rect clipRect{0, 0};
                SDL_GetRendererOutputSize(context().renderer, &clipRect.w, &clipRect.h);
                context().renderer.setClipRect(clipRect);
                current_session->root_widget->paint();
            }

            int mx, my;
            SDL_GetMouseState(&mx, &my);

            if (SDL_GetKeyboardState(nullptr)[SDL_SCANCODE_F3]) {
                if (current_session->mouse_focused_widget != nullptr) {
                    context().renderer.setColor(0xFF, 0x00, 0x00);
                    context().renderer.drawRect(current_session->mouse_focused_widget->actual_bounds);
                }

                if (current_session->keyboard_focused_widget != nullptr) {
                    context().renderer.setColor(0x00, 0xFF, 0x00);
                    context().renderer.drawRect(current_session->keyboard_focused_widget->actual_bounds);
                }
            }

            context().renderer.present();

            if ((windowFlags & (SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_MOUSE_FOCUS)) != 0) {
                // 60 FPS with focused window
                SDL_Delay(16);
            } else {
                // 30 FPS with window in backgound
                SDL_Delay(33);
            }
        } else {
            // slow update loop when window is not visible
            SDL_Delay(100);
        }
    }

    current_rc.reset();

    SDL_DestroyWindow(window);

    return 0;
}

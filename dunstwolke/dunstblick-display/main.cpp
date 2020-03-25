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

static std::ostream & operator<<(std::ostream & stream, CallbackID cb)
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

Session & get_current_session()
{
    assert(current_session != nullptr);
    return *current_session;
}

int main()
{

    xnet::endpoint target_endpoint;
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

        struct Client
        {
            std::string name;
            uint16_t tcp_port;
            xnet::endpoint udp_ep;
        };

        std::vector<Client> clients;

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
                    if (errno != ETIMEDOUT)
                        perror("receive failed");
                    break;
                }
                if (len >= sizeof(UdpDiscoverResponse) and message.header.type == UDP_RESPOND_DISCOVER) {
                    auto & resp = message.discover_response;
                    if (resp.length < DUNSTBLICK_MAX_APP_NAME_LENGTH)
                        resp.name[resp.length] = 0;
                    else
                        resp.name.back() = 0;

                    Client client;

                    client.name = std::string(resp.name.data());
                    client.tcp_port = resp.tcp_port;
                    client.udp_ep = sender;

                    bool found = false;
                    for (auto const & other : clients) {
                        if (client.tcp_port != other.tcp_port)
                            continue;
                        if (client.udp_ep != other.udp_ep)
                            continue;
                        found = true;
                        break;
                    }
                    if (found)
                        continue;
                    clients.emplace_back(std::move(client));
                }
            }
        }

        for (auto const & client : clients) {
            printf("%s:\n"
                   "\tname: %s\n"
                   "\tport: %d\n",
                   xnet::to_string(client.udp_ep).c_str(),
                   client.name.c_str(),
                   client.tcp_port);
        }

        if (clients.size() == 0)
            return 1;

        auto const & client_meta = clients.at(0);

        switch (client_meta.udp_ep.family()) {
            case AF_INET:
                target_endpoint = xnet::endpoint(client_meta.udp_ep.get_addr_v4(), client_meta.tcp_port);
                break;
            case AF_INET6:
                target_endpoint = xnet::endpoint(client_meta.udp_ep.get_addr_v6(), client_meta.tcp_port);
                break;
            default:
                return 1;
        }
    }

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

    Session sess{target_endpoint};

    current_session = &sess;

    while (not shutdown_app_requested) {
        current_session->do_communication();

        if (not current_session->is_active) {
            break;
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

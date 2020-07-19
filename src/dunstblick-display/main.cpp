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

#include "session.hpp"

#include "rendercontext.hpp"
#include "zigsession.hpp"

#include "dunstblick-internal.hpp"

[[noreturn]] static void exit_sdl_error(char const * msg = nullptr)
{
    fprintf(stderr, "%s: %s\n", (msg != nullptr) ? msg : "sdl error", SDL_GetError());
    fflush(stdout);
    fflush(stderr);
    exit(1);
}

std::unique_ptr<RenderContext> current_rc;

// #include <iostream>

// static std::ostream & operator<<(std::ostream & stream, std::monostate)
// {
//     stream << "<NULL>";
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, ObjectRef ref)
// {
//     stream << "→[" << ref.id.value << "]";
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, EventID cb)
// {
//     stream << "{" << cb.value << "}";
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, ObjectList const & list)
// {
//     stream << "[";
//     for (auto const & val : list) {
//         stream << " " << val;
//     }
//     stream << " ]";
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, UIMargin)
// {
//     stream << "<margin>";
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, UIColor col)
// {
//     stream << std::setw(2) << std::hex << "r=" << col.r << ", g=" << col.g << ", b=" << col.b << ", a=" << col.a;
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, UISize val)
// {
//     stream << val.w << " × " << val.h;
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, UIPoint val)
// {
//     stream << val.x << ", " << val.y;
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, UIResourceID)
// {
//     stream << "<ui resource id>";
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, UISizeList)
// {
//     stream << "<ui size list>";
//     return stream;
// }

// static std::ostream & operator<<(std::ostream & stream, WidgetName name)
// {
//     stream << "/" << name.value << "/";
//     return stream;
// }

// static void dump_object(Object const & obj)
// {
//     std::cout << "Object[" << obj.get_id().value << "]" << std::endl;
//     for (auto const & prop : obj.properties) {
//         std::cout << "\t[" << prop.first.value << "] : " << to_string(prop.second.type) << " = ";
//         std::visit([](auto const & val) { std::cout << val; }, prop.second.value);
//         std::cout << std::endl;
//     }
// }

static Widget * keyboard_focused_widget = nullptr;
static Widget * mouse_focused_widget = nullptr;

static Widget * get_mouse_widget(Session * session, int x, int y)
{
    if (not session->root_widget)
        return nullptr;
    else if (Widget::capturingWidget)
        return Widget::capturingWidget;
    else
        return session->root_widget->hitTest(x, y);
}

static void ui_set_keyboard_focus(Session * session, Widget * widget)
{
    if (session->keyboard_focused_widget == widget)
        return;

    if (session->keyboard_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_LOST_KEYBOARD_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        session->keyboard_focused_widget->processEvent(e);
    }
    session->keyboard_focused_widget = widget;
    if (session->keyboard_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_GOT_KEYBOARD_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        session->keyboard_focused_widget->processEvent(e);
    }
}

static void ui_set_mouse_focus(Session * session, Widget * widget)
{
    if (session->mouse_focused_widget == widget)
        return;

    if (session->mouse_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_LOST_MOUSE_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        session->mouse_focused_widget->processEvent(e);
    }
    session->mouse_focused_widget = widget;
    if (session->mouse_focused_widget != nullptr) {
        SDL_Event e;
        e.type = UI_EVENT_GOT_MOUSE_FOCUS;
        e.common.timestamp = SDL_GetTicks();
        session->mouse_focused_widget->processEvent(e);
    }
}

extern "C" void session_pushEvent(ZigSession * current_session, SDL_Event const * ev)
{
    SDL_Event const & e = *ev;
    switch (e.type) {
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
            current_session->mouse_pos.x = e.motion.x;
            current_session->mouse_pos.y = e.motion.y;
            if (not current_session->root_widget)
                break;
            if (auto * child = get_mouse_widget(current_session, e.motion.x, e.motion.y); child != nullptr) {
                // only move focus if mouse is not captured
                if (Widget::capturingWidget == nullptr)
                    ui_set_mouse_focus(current_session, child);
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

            if (auto * child = get_mouse_widget(current_session, e.button.x, e.button.y); child != nullptr) {
                ui_set_mouse_focus(current_session, child);

                if ((e.type == SDL_MOUSEBUTTONUP) and child->isKeyboardFocusable())
                    ui_set_keyboard_focus(current_session, child);

                child->processEvent(e);
            }
            break;
        }

        case SDL_MOUSEWHEEL: {
            if (not current_session->root_widget)
                break;
            if (auto * child =
                    get_mouse_widget(current_session, current_session->mouse_pos.x, current_session->mouse_pos.y);
                child != nullptr) {
                ui_set_mouse_focus(current_session, child);

                child->processEvent(e);
            }
            break;
        }
    }
}

extern "C" SDL_SystemCursor session_getCursor(ZigSession * sess)
{
    SDL_SystemCursor nextCursor;
    if (mouse_focused_widget)
        nextCursor = mouse_focused_widget->getCursor(sess->mouse_pos);
    else
        nextCursor = SDL_SYSTEM_CURSOR_ARROW;
    return nextCursor;

    // if (nextCursor != currentCursor) {
    //     currentCursor = nextCursor;
    //     SDL_SetCursor(cursors[currentCursor].get());
    // }
}

extern "C" void session_render(ZigSession * session)
{
    RenderContext current_rc;

    // current_rc->renderer.resetClipRect();
    // assert(not current_rc->renderer.isClipEnabled());

    // current_rc->renderer.setColor(0x00, 0x00, 0x00, 0xFF);
    // current_rc->renderer.fillRect(current_rc->renderer.getViewport());

    session->update_layout(current_rc);

    if (session->root_widget) {
        Rectangle clipRect{0, 0, 0, 0};
        // SDL_GetRendererOutputSize(current_rc->renderer, &clipRect.w, &clipRect.h);
        // current_rc->renderer.setClipRect(clipRect);
        session->root_widget->paint(current_rc);
    }

    // int mx, my;
    // SDL_GetMouseState(&mx, &my);

    // if (SDL_GetKeyboardState(nullptr)[SDL_SCANCODE_F3]) {
    //     if (mouse_focused_widget != nullptr) {
    //         current_rc->renderer.setColor(0xFF, 0x00, 0x00);
    //         current_rc->renderer.drawRect(mouse_focused_widget->actual_bounds);
    //     }

    //     if (keyboard_focused_widget != nullptr) {
    //         current_rc->renderer.setColor(0x00, 0xFF, 0x00);
    //         current_rc->renderer.drawRect(keyboard_focused_widget->actual_bounds);
    //     }
    // }
}

// void local_sess_update()
// {

//     std::vector<DiscoveredClient> clients;
//     {
//         std::lock_guard<std::mutex> lock{discovered_clients_lock};
//         clients = discovered_clients;
//     }

//     ObjectList list;
//     list.reserve(clients.size());

//     for (size_t i = 0; i < clients.size(); i++) {
//         auto const id = local_session_id(i);

//         Object obj{id};

//         obj.add(local_app_name, UIValue(clients[i].name));
//         obj.add(local_app_port, UIValue(clients[i].tcp_port));
//         obj.add(local_app_ip, UIValue(xnet::to_string(clients[i].udp_ep, false)));
//         obj.add(local_app_id, UIValue(WidgetName(i + 1)));

//         list.emplace_back(obj);

//         sess.addOrUpdateObject(std::move(obj));
//     }

//     sess.clear(local_root_obj, local_discovery_list);
//     sess.insertRange(local_root_obj, local_discovery_list, 0, list.size(), list.data());
// }

// ObjectID constexpr local_root_obj{1};

// UIResourceID constexpr local_discovery_list_item{1};

// PropertyName constexpr local_discovery_list{1};
// PropertyName constexpr local_app_name{2};
// PropertyName constexpr local_app_ip{3};
// PropertyName constexpr local_app_port{4};
// PropertyName constexpr local_app_id{5};

// EventID constexpr local_exit_client_event{1};
// EventID constexpr local_open_session_event{2};
// EventID constexpr local_close_session_event{3};

// void foobar_create_local_sess()
// {
//     LocalSession sess;

//     sess.onEvent = [](EventID event, WidgetName widget) {

//     };

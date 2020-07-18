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
#include "rendercontext.hpp"

#include "dunstblick-internal.hpp"

static bool shutdown_app_requested = false;

[[noreturn]] static void exit_sdl_error(char const * msg = nullptr)
{
    fprintf(stderr, "%s: %s\n", (msg != nullptr) ? msg : "sdl error", SDL_GetError());
    fflush(stdout);
    fflush(stderr);
    exit(1);
}

std::unique_ptr<RenderContext> current_rc;

SDL_Rect screen_rect = {0, 0, 0, 0};

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

static Widget * keyboard_focused_widget = nullptr;
static Widget * mouse_focused_widget = nullptr;

Widget * get_mouse_widget(int x, int y)
{
    if (not current_session->root_widget)
        return nullptr;
    else if (Widget::capturingWidget)
        return Widget::capturingWidget;
    else
        return current_session->root_widget->hitTest(x, y);
}

void ui_set_keyboard_focus(Widget * widget)
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

void ui_set_mouse_focus(Widget * widget)
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

int old_main()
{

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

    current_rc->renderer.setBlendMode(SDL_BLENDMODE_BLEND); // enable alpha blend

    auto const startup = SDL_GetTicks();

    xstd::resource<SDL_Cursor *, SDL_FreeCursor> cursors[SDL_NUM_SYSTEM_CURSORS];
    for (size_t i = 0; i < SDL_NUM_SYSTEM_CURSORS; i++) {
        cursors[i].reset(SDL_CreateSystemCursor(SDL_SystemCursor(i)));
        assert(cursors[i] != nullptr);
    }

    SDL_SystemCursor currentCursor = SDL_SYSTEM_CURSOR_ARROW;
    SDL_SetCursor(cursors[currentCursor].get());

    UIPoint mouse_pos{0, 0};

    {

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

                auto const net_sess = new NetworkSession(client.create_tcp_endpoint());

                net_sess->title = client.name;

                net_sess->onWidgetDestroyed = [](Widget * w) {
                    // focused widgets are destroyed, so remove the reference here!
                    if (keyboard_focused_widget == w)
                        keyboard_focused_widget = nullptr;
                    if (mouse_focused_widget == w)
                        mouse_focused_widget = nullptr;
                };

                all_sessions.emplace_back(net_sess);

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
        sess.root_widget->margins.set(sess.root_widget.get(), UIMargin(0));
        {
            auto * const menu = new DockLayout();
            menu->tabTitle.set(menu, "Menu");

            auto * const quitLabel = new Label();
            quitLabel->text.set(quitLabel, "Exit");

            auto * const quitButton = new Button();
            quitButton->onClickEvent.set(quitButton, local_exit_client_event);
            quitButton->dockSite.set(quitButton, DockSite::bottom);
            quitButton->getChildContainer().emplace_back(quitLabel);

            menu->getChildContainer().emplace_back(quitButton);

            auto * const headerLabel = new Label();
            headerLabel->text.set(headerLabel, "Available Applications");
            headerLabel->font.set(headerLabel, UIFont::serif);

            menu->getChildContainer().emplace_back(headerLabel);

            auto * const serviceList = new StackLayout();
            serviceList->bindingContext.set(serviceList, ObjectRef{local_root_obj});
            serviceList->childSource.binding = local_discovery_list;
            serviceList->childTemplate.set(serviceList, local_discovery_list_item);

            auto * const serviceScroll = new ScrollView();

            serviceScroll->getChildContainer().emplace_back(serviceList);

            menu->getChildContainer().emplace_back(serviceScroll);

            sess.root_widget->getChildContainer().emplace_back(menu);
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
                auto & children = sess.root_widget->getChildContainer();

                for (size_t i = 0; i < all_sessions.size(); i++) {

                    auto const session = all_sessions.at(i).get();

                    size_t child_index = i + 1;

                    Widget * container;
                    if (child_index >= children.size()) {
                        container = new Container();
                        container->widget_context = sess.root_widget->widget_context;
                        children.emplace_back(container);

                        reinterpret_cast<TabLayout *>(sess.root_widget.get())
                            ->selectedIndex.set(sess.root_widget.get(), int(child_index));
                    } else {
                        container = children.at(child_index).get();
                    }
                    container->tabTitle.set(container, session->title);

                    if (session->root_widget) {
                        auto root = session->root_widget.get();
                        if (container->getChildContainer().size() == 0)
                            container->getChildContainer().emplace_back(root);
                        else {
                            container->getChildContainer().at(0).release();
                            container->getChildContainer().at(0).reset(root);
                        }
                    } else {
                        if (container->getChildContainer().size() > 0) {
                            assert(container->getChildContainer().size() == 1);
                            container->getChildContainer().at(0).release();
                            container->getChildContainer().clear();
                        }
                    }
                }
                while (sess.root_widget->getChildContainer().size() > all_sessions.size() + 1) {
                    // we do evel hackery above and store the same pointer in two
                    // unique pointers. We have to make sure that we don't double free it.
                    sess.root_widget->getChildContainer().back().release();
                    sess.root_widget->getChildContainer().pop_back();
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
                        if (keyboard_focused_widget != nullptr) {
                            keyboard_focused_widget->processEvent(e);
                        }
                        break;
                    }

                    // mouse events:
                    case SDL_MOUSEMOTION: {
                        mouse_pos.x = e.motion.x;
                        mouse_pos.y = e.motion.y;
                        if (not current_session->root_widget)
                            break;
                        if (auto * child = get_mouse_widget(e.motion.x, e.motion.y); child != nullptr) {
                            // only move focus if mouse is not captured
                            if (Widget::capturingWidget == nullptr)
                                ui_set_mouse_focus(child);
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

                        if (auto * child = get_mouse_widget(e.button.x, e.button.y); child != nullptr) {
                            ui_set_mouse_focus(child);

                            if ((e.type == SDL_MOUSEBUTTONUP) and child->isKeyboardFocusable())
                                ui_set_keyboard_focus(child);

                            child->processEvent(e);
                        }
                        break;
                    }

                    case SDL_MOUSEWHEEL: {
                        if (not current_session->root_widget)
                            break;
                        if (auto * child = get_mouse_widget(mouse_pos.x, mouse_pos.y); child != nullptr) {
                            ui_set_mouse_focus(child);

                            child->processEvent(e);
                        }
                        break;
                    }
                }
            }

            SDL_SystemCursor nextCursor;
            if (mouse_focused_widget)
                nextCursor = mouse_focused_widget->getCursor(mouse_pos);
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
                current_rc->renderer.resetClipRect();
                assert(not current_rc->renderer.isClipEnabled());

                current_rc->renderer.setColor(0x00, 0x00, 0x00, 0xFF);
                current_rc->renderer.fillRect(current_rc->renderer.getViewport());

                current_session->update_layout();

                if (current_session->root_widget) {
                    Rectangle clipRect{0, 0, 0, 0};
                    SDL_GetRendererOutputSize(current_rc->renderer, &clipRect.w, &clipRect.h);
                    current_rc->renderer.setClipRect(clipRect);
                    current_session->root_widget->paint(*current_rc);
                }

                int mx, my;
                SDL_GetMouseState(&mx, &my);

                if (SDL_GetKeyboardState(nullptr)[SDL_SCANCODE_F3]) {
                    if (mouse_focused_widget != nullptr) {
                        current_rc->renderer.setColor(0xFF, 0x00, 0x00);
                        current_rc->renderer.drawRect(mouse_focused_widget->actual_bounds);
                    }

                    if (keyboard_focused_widget != nullptr) {
                        current_rc->renderer.setColor(0x00, 0xFF, 0x00);
                        current_rc->renderer.drawRect(keyboard_focused_widget->actual_bounds);
                    }
                }

                current_rc->renderer.present();

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

        while (sess.root_widget->getChildContainer().size() > 1) {
            // we do evel hackery above and store the same pointer in two
            // unique pointers. We have to make sure that we don't double free it.
            sess.root_widget->getChildContainer().back().release();
            sess.root_widget->getChildContainer().pop_back();
        }

        for (auto & s : all_sessions) {
            s->onWidgetDestroyed = [](Widget *) {};
        }
        sess.onWidgetDestroyed = [](Widget *) {};
    }

    current_rc.reset();

    SDL_DestroyWindow(window);

    return 0;
}

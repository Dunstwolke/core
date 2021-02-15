#include <SDL.h>
#include <filesystem>
#include <vector>

#include "layouts.hpp"
#include "resources.hpp"
#include "types.hpp"
#include "widget.hpp"
#include "widgets.hpp"

#include "inputstream.hpp"

#include "enums.hpp"
#include "resources.hpp"
#include "types.hpp"

#include "session.hpp"

#include "rendercontext.hpp"
#include "zigsession.hpp"

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

extern "C" void session_render(ZigSession * session, Rectangle screen_rect, PainterAPI * painter)
{
    RenderContext current_rc{painter};

    session->screen_rect = screen_rect;
    session->update_layout(current_rc);

    if (session->root_widget) {
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

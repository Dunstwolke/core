#include "session.hpp"

#include "rendercontext.hpp"
#include <xlog>

#include <SDL_image.h>

#include "widget.hpp"

extern SDL_Rect screen_rect;

Session::Session() {}

Session::~Session() {}

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
    root_widget->initializeRoot(this);

    // focused widgets are destroyed, so remove the reference here!
    keyboard_focused_widget = nullptr;
    mouse_focused_widget = nullptr;

    update_layout();
}

void Session::setRoot(ObjectID id)
{
    auto ref = ObjectRef{id};
    if (auto obj = ref.try_resolve(*this); obj) {
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
    if (auto obj = ObjectRef{oid}.try_resolve(*this); obj) {
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

static inline xstd::optional<ObjectList &> get_list(Session & sess, ObjectID oid, PropertyName name)
{
    if (auto obj = ObjectRef{oid}.try_resolve(sess); obj) {
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
    if (auto list = get_list(*this, obj, prop); list) {
        list->clear();
    }
}

void Session::insertRange(ObjectID obj, PropertyName prop, size_t index, size_t count, const ObjectRef * value)
{
    if (auto list = get_list(*this, obj, prop); list) {
        for (size_t i = 0; i < count; i++, index++) {
            list->emplace((index >= list->size()) ? list->end() : list->begin() + gsl::narrow<ssize_t>(index),
                          value[i]);
        }
    }
}

void Session::removeRange(ObjectID obj, PropertyName prop, size_t index, size_t count)
{
    if (auto list = get_list(*this, obj, prop); list) {
        if (list->empty())
            return;
        for (size_t i = 0; (i < count) and (index < list->size()); i++, index++) {
            list->erase(list->begin() + gsl::narrow<ssize_t>(index));
        }
    }
}

void Session::moveRange(ObjectID obj, PropertyName prop, size_t indexFrom, size_t indexTo, size_t count)
{
    if (auto list = get_list(*this, obj, prop); list) {
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

Object & Session::add_or_update_object(Object && obj)
{
    if (auto it = object_registry.find(obj.get_id()); it != object_registry.end()) {
        assert(it->first == obj.get_id());
        it->second = std::move(obj);
        return it->second;
    }
    auto [it, emplaced] = object_registry.emplace(obj.get_id(), std::move(obj));
    assert(emplaced);
    return it->second;
}

Object & Session::add_or_get_object(ObjectID id)
{
    if (auto it = object_registry.find(id); it != object_registry.end()) {
        assert(it->first == id);
        return it->second;
    }
    auto [it, emplaced] = object_registry.emplace(id, Object{id});
    assert(emplaced);
    return it->second;
}

void Session::destroy_object(ObjectID id)
{
    object_registry.erase(id);
}

const std::map<ObjectID, Object> & Session::get_object_registry()
{
    return object_registry;
}

xstd::optional<Object &> Session::try_resolve(ObjectID id)
{
    if (id.is_null())
        return xstd::nullopt;

    if (auto it = object_registry.find(id); it != object_registry.end())
        return it->second;
    else
        return xstd::nullopt;
}

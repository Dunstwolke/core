#ifndef SESSION_HPP
#define SESSION_HPP

#include <mutex>
#include <vector>

#include "enums.hpp"
#include "resources.hpp"
#include "types.hpp"

using Packet = std::vector<uint8_t>;

struct Widget;

struct Session
{
    std::unique_ptr<Widget> root_widget;
    Widget * keyboard_focused_widget = nullptr;
    Widget * mouse_focused_widget = nullptr;

    ObjectRef root_object = ObjectRef(nullptr);

    std::mutex send_lock;

    bool is_active = true;

    std::map<UIResourceID, Resource> resources;
    std::map<ObjectID, Object> object_registry;

    Session();
    Session(Session const &) = delete;
    virtual ~Session();

    virtual void update() = 0;

    // API
    void uploadResource(UIResourceID, ResourceKind, void const * data, size_t len);
    void addOrUpdateObject(Object && obj);
    void removeObject(ObjectID id);
    void setView(UIResourceID id);
    void setRoot(ObjectID obj);
    void setProperty(
        ObjectID obj,
        PropertyName prop,
        UIValue const & value); // "unsafe command", uses the serverside object type or fails of property does not exist
    void clear(ObjectID obj, PropertyName prop);
    void insertRange(
        ObjectID obj, PropertyName prop, size_t index, size_t count, ObjectRef const * value);       // manipulate lists
    void removeRange(ObjectID obj, PropertyName prop, size_t index, size_t count);                   // manipulate lists
    void moveRange(ObjectID obj, PropertyName prop, size_t indexFrom, size_t indexTo, size_t count); // manipulate lists

    // Event handling
    virtual void trigger_event(CallbackID cid) = 0;

    virtual void trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value) = 0;

    // Layouting and stuff
    void update_layout();
    void ui_set_mouse_focus(Widget * widget);
    void ui_set_keyboard_focus(Widget * widget);

    Widget * get_mouse_widget(int x, int y);

    // More

    /// loads a widget from a given resource ID or throws.
    std::unique_ptr<Widget> load_widget(UIResourceID id);

    // Resource handling:

    xstd::optional<Resource const &> find_resource(UIResourceID id);

    template <typename T>
    xstd::optional<T const &> get_resource(UIResourceID id)
    {
        if (auto res = find_resource(id); res and std::holds_alternative<T>(*res))
            return std::get<T>(*res);
        else
            return xstd::nullopt;
    }

    void set_resource(UIResourceID id, Resource && resource);

    // Object handling:

    Object & add_or_get_object(ObjectID id);

    Object & add_or_update_object(Object && obj);

    void destroy_object(ObjectID id);

    std::map<ObjectID, Object> const & get_object_registry();
};

Session & get_current_session();

#endif // SESSION_HPP
